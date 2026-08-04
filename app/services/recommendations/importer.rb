require "digest"
require "set"

module Recommendations
  # 파싱된 어린이 분과 도서를 카탈로그에 ISBN 우선 upsert하고, 성공한 import 하나만
  # 학생 홈의 활성 추천 목록으로 만든다. 동일 파일 재업로드는 digest 로 멱등 처리한다.
  class Importer
    class Error < StandardError; end

    Result = Struct.new(:recommendation_import, :reused, keyword_init: true)

    # 최초 설치용 번들 추천도서 XLSX 의 위치 단일 진실(`db/seeds.rb` 초기 적재와 파싱 계약
    # 테스트가 공유). **`db/seeds` 에 두는 이유**: 이 파일은 시드 입력이라 저장소에 함께 있어야
    # 클론·CI 체크아웃에서도 추천 목록이 비지 않는데, 예전 위치인 `docs/` 는 중첩 git 저장소라
    # 바깥 저장소가 그 안의 파일을 추적할 수 없다. `docs/` 는 로컬 문서 저장소를 그대로 둔
    # 개발자를 위한 폴백으로만 남긴다. 파일명은 "추천도서목록" 포함으로 찾으며(호수·판본이 바뀌어도
    # 매칭), macOS 등에서 자모 분리(NFD) 저장된 이름도 걸리도록 NFC 정규화 후 비교한다.
    def self.bundled_workbook_path
      Dir[
        Rails.root.join("db", "seeds", "*.xlsx"),
        Rails.root.join("docs", "*.xlsx")
      ].find { |path| File.basename(path).unicode_normalize(:nfc).include?("추천도서목록") }
    end

    def initialize(path:, filename:)
      @path = path.to_s
      @filename = File.basename(filename.to_s).presence || "recommendations.xlsx"
    end

    def call(imported_by: nil)
      raise Error, "XLSX 파일만 업로드할 수 있습니다." unless File.extname(@filename).casecmp?(".xlsx")

      @enrich_book_ids = []
      @summary_book_ids = []

      reader = XlsxReader.new(@path)
      entries = reader.read
      missing_isbn_count = entries.count { |entry| entry.isbn.blank? }
      if missing_isbn_count.positive?
        raise Error, "ISBN이 없는 추천도서 #{missing_isbn_count}권은 등록할 수 없습니다."
      end
      invalid_isbn_count = entries.count { |entry| Books::Isbn.normalize(entry.isbn).nil? }
      if invalid_isbn_count.positive?
        raise Error, "유효하지 않은 ISBN 추천도서 #{invalid_isbn_count}권은 등록할 수 없습니다."
      end
      digest = Digest::SHA256.file(@path).hexdigest

      result = RecommendationImport.transaction do
        if (existing = RecommendationImport.find_by(file_digest: digest))
          activate!(existing)
          Result.new(recommendation_import: existing, reused: true)
        else
          recommendation_import = RecommendationImport.create!(
            filename: @filename,
            file_digest: digest,
            source_title: reader.source_title,
            imported_by: imported_by,
            imported_at: Time.current
          )

          seen_book_ids = Set.new
          entries.each do |entry|
            book = upsert_book!(entry)
            next unless seen_book_ids.add?(book.id)

            recommendation_import.book_recommendations.create!(
              book: book,
              issue: entry.issue,
              section: entry.section,
              published_on: entry.published_on,
              position: seen_book_ids.size
            )
          end

          recommendation_import.update!(item_count: seen_book_ids.size)
          activate!(recommendation_import)
          Result.new(recommendation_import: recommendation_import, reused: false)
        end
      end

      # 업로드 응답을 네이버 왕복으로 지연시키지 않는다. 동일 파일 재업로드 때도 다시
      # enqueue하여 이전 무키/일시 실패로 남은 표지를 자연스럽게 재시도한다(잡은 멱등).
      RecommendationCoverEnrichmentJob.perform_later(result.recommendation_import.id)
      # 장르 공란 도서는 무API 추론 잡(BookEnrichmentJob)으로 비동기 보강한다(멱등).
      # 추천 XLSX 유입 도서는 시드 사전계산·네이버 검색 경로를 모두 우회해 무장르로 남으므로,
      # SearchService 신규 유입과 같은 자동 보강 트리거를 이 경로에도 건다(표지 잡과 동일 커밋 후 시점).
      @enrich_book_ids.each { |book_id| BookEnrichmentJob.perform_later(book_id) }
      # 줄거리 미확인 도서도 같은 이유로 BookSummaryJob 예약(genre 보강 미러, 게임 재구성 Phase 4
      # code-review 후속). 추천 XLSX 유입은 온디맨드 워밍(resolve)을 거치지 않아 content_provider
      # 의 §1d 트리거가 안 걸리므로, 신규 유입 커버를 위해 임포터가 직접 예약한다. 잡이 무키
      # no-op·멱등이라 안전(BookEnrichmentJob 과 동형 — 조건 없이 항상 예약, 잡이 내부 가드).
      @summary_book_ids.each { |book_id| BookSummaryJob.perform_later(book_id) }
      result
    rescue XlsxReader::Error => error
      raise Error, error.message
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      raise Error, "추천도서를 저장하지 못했습니다: #{error.message}"
    end

    private

    def activate!(recommendation_import)
      RecommendationImport.where.not(id: recommendation_import.id).active.update_all(active: false, updated_at: Time.current)
      recommendation_import.update!(active: true) unless recommendation_import.active?
    end

    def upsert_book!(entry)
      book = Book.find_or_initialize_by(isbn: Books::Isbn.normalize(entry.isbn))

      book.assign_attributes(
        title: entry.title,
        author: entry.author,
        publisher: entry.publisher
      )
      book.category = :recommended if book.new_record? || book.searched?
      book.save!
      @enrich_book_ids << book.id if book.genre.blank?
      @summary_book_ids << book.id if book.summary.blank? && book.summary_checked_at.nil?
      book
    end
  end
end
