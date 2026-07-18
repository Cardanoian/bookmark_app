require "digest"
require "set"

module Recommendations
  # 파싱된 어린이 분과 도서를 카탈로그에 ISBN 우선 upsert하고, 성공한 import 하나만
  # 학생 홈의 활성 추천 목록으로 만든다. 동일 파일 재업로드는 digest 로 멱등 처리한다.
  class Importer
    class Error < StandardError; end

    Result = Struct.new(:recommendation_import, :reused, keyword_init: true)

    def initialize(path:, filename:)
      @path = path.to_s
      @filename = File.basename(filename.to_s).presence || "recommendations.xlsx"
    end

    def call(imported_by: nil)
      raise Error, "XLSX 파일만 업로드할 수 있습니다." unless File.extname(@filename).casecmp?(".xlsx")

      reader = XlsxReader.new(@path)
      entries = reader.read
      digest = Digest::SHA256.file(@path).hexdigest

      RecommendationImport.transaction do
        if (existing = RecommendationImport.find_by(file_digest: digest))
          activate!(existing)
          return Result.new(recommendation_import: existing, reused: true)
        end

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
      book = if entry.isbn.present?
        Book.find_or_initialize_by(isbn: entry.isbn)
      else
        Book.find_or_initialize_by(title: entry.title, author: entry.author)
      end

      book.assign_attributes(
        title: entry.title,
        author: entry.author,
        publisher: entry.publisher
      )
      book.category = :recommended if book.new_record? || book.searched?
      book.save!
      book
    end
  end
end
