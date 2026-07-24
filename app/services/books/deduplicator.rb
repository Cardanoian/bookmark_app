module Books
  # 도서 카탈로그 중복을 대표 Book 한 행으로 병합한다.
  #
  # 탐지 대상:
  # 1) 하이픈·공백 표기 또는 ISBN-10/13 차이만 있는 유효 ISBN 중복
  # 2) ISBN은 비었지만 제목·저자·출판사가 ISBN 보유 도서 하나와 확실히 일치하는 그림자 중복
  #
  # 기본 호출은 dry-run이며 apply: true 일 때만 참조 이관·중복 삭제를 수행한다. 시스템 퀴즈의
  # 콘텐츠축 유니크 키가 충돌하는 그룹은 데이터 손실을 피하기 위해 통째로 건너뛴다.
  class Deduplicator
    Group = Struct.new(:kind, :key, :canonical, :duplicates, keyword_init: true)
    Outcome = Struct.new(:group, :status, :reason, keyword_init: true)
    Result = Struct.new(:outcomes, :apply, keyword_init: true) do
      def detected_count = outcomes.size
      def merged_count = outcomes.count { |outcome| outcome.status == :merged }
      def ready_count = outcomes.count { |outcome| outcome.status == :ready }
      def skipped_count = outcomes.count { |outcome| outcome.status == :skipped }
      def error_count = outcomes.count { |outcome| outcome.status == :error }
      def deleted_count = outcomes.select { |outcome| outcome.status == :merged }
                              .sum { |outcome| outcome.group.duplicates.size }
    end

    SIMPLE_REFERENCE_MODELS = [ BookIntro, Challenge, LibraryEvent, Quiz, Report, Topic ].freeze
    REFERENCE_MODELS = (SIMPLE_REFERENCE_MODELS + [ BookRecommendation, GamePlay ]).freeze
    MERGE_FIELDS = %i[author cover_url publisher summary grade_band genre].freeze

    def initialize(scope: Book.all, apply: false, include_shadows: true)
      @scope = scope
      @apply = apply
      @include_shadows = include_shadows
    end

    def call
      outcomes = process(isbn_groups)
      # 실제 병합에서는 ISBN 그룹 삭제 결과를 반영해 그림자 후보를 다시 계산한다.
      outcomes.concat(process(shadow_groups)) if @include_shadows
      Result.new(outcomes: outcomes, apply: @apply)
    end

    # 유효 ISBN만 정규화한다. ISBN-10은 동등한 978 ISBN-13으로 변환해 서로 같은 그룹으로 묶는다.
    def self.normalize_isbn(raw)
      Books::Isbn.normalize(raw)
    end

    private

    def process(groups)
      groups.map do |group|
        if (reason = unsafe_reason(group))
          Outcome.new(group: group, status: :skipped, reason: reason)
        elsif @apply
          merge_group(group)
        else
          Outcome.new(group: group, status: :ready)
        end
      rescue StandardError => error
        Rails.logger.error(
          "Books::Deduplicator failed for #{group.kind}/#{group.key}: #{error.class}: #{error.message}"
        )
        Outcome.new(group: group, status: :error, reason: "#{error.class}: #{error.message}")
      end
    end

    def isbn_groups
      grouped = @scope.where.not(isbn: [ nil, "" ]).to_a.group_by do |book|
        self.class.normalize_isbn(book.isbn)
      end

      grouped.filter_map do |isbn, books|
        next if isbn.nil? || books.size < 2

        canonical = choose_canonical(books)
        Group.new(kind: :isbn, key: isbn, canonical: canonical, duplicates: books - [ canonical ])
      end
    end

    # ISBN 공란 도서는 제목·저자·출판사 정규화가 모두 맞고 ISBN 보유 후보가 정확히 하나일 때만
    # 자동 병합 후보로 삼는다. 판본이 다른 고전·번역서처럼 출판사가 다르면 보고 대상에도 넣지 않는다.
    def shadow_groups
      isbn_books_by_title = @scope.where.not(isbn: [ nil, "" ]).to_a.group_by do |book|
        normalize_text(book.title)
      end

      @scope.where(isbn: [ nil, "" ]).filter_map do |shadow|
        candidates = Array(isbn_books_by_title[normalize_text(shadow.title)]).select do |candidate|
          self.class.normalize_isbn(candidate.isbn).present? && shadow_match?(shadow, candidate)
        end
        next unless candidates.one?

        canonical = candidates.first
        Group.new(
          kind: :shadow,
          key: self.class.normalize_isbn(canonical.isbn),
          canonical: canonical,
          duplicates: [ shadow ]
        )
      end
    end

    def shadow_match?(shadow, candidate)
      shadow_author = normalize_text(shadow.author)
      candidate_author = normalize_text(candidate.author)
      shadow_publisher = normalize_text(shadow.publisher)
      candidate_publisher = normalize_text(candidate.publisher)

      return false if shadow_author.blank? || candidate_author.blank?
      return false if shadow_publisher.blank? || shadow_publisher != candidate_publisher

      shadow_author.include?(candidate_author) || candidate_author.include?(shadow_author)
    end

    def normalize_text(value)
      value.to_s.unicode_normalize(:nfkc).downcase
           .gsub(/<[^>]+>/, "").gsub(/[^0-9a-z가-힣]/, "")
    end

    def choose_canonical(books)
      books.min_by do |book|
        [ category_rank(book), -reference_count(book), -metadata_score(book), book.id ]
      end
    end

    def category_rank(book)
      return 0 if book.classic?
      return 1 if book.recommended?

      2
    end

    def reference_count(book)
      REFERENCE_MODELS.sum { |model| model.where(book_id: book.id).count }
    end

    def metadata_score(book)
      MERGE_FIELDS.count { |field| book.public_send(field).present? }
    end

    # system quiz는 병합 후 (book, band, axis, version) 부분 유니크 인덱스에 충돌할 수 있다.
    # 서로 다른 문항/응답을 임의로 버릴 수 없으므로 이런 그룹은 운영자가 먼저 검토하도록 skip한다.
    def unsafe_reason(group)
      ids = [ group.canonical.id, *group.duplicates.map(&:id) ]
      collisions = Quiz.where(book_id: ids, origin: Quiz.origins[:system])
                       .where.not(band: nil).where.not(content_axis: nil).where.not(content_version: nil)
                       .group(:band, :content_axis, :content_version)
                       .having("COUNT(*) > 1").count
      collisions.any? ? "system quiz content key conflict" : nil
    end

    def merge_group(group)
      canonical = group.canonical
      duplicates = group.duplicates
      affected_import_ids = []

      Book.transaction do
        merged_attributes = merged_attributes(canonical, duplicates)
        duplicate_ids = duplicates.map(&:id)

        affected_import_ids = move_recommendations!(canonical, duplicate_ids)
        move_game_plays!(canonical, duplicate_ids)
        SIMPLE_REFERENCE_MODELS.each do |model|
          model.where(book_id: duplicate_ids).update_all(book_id: canonical.id, updated_at: Time.current)
        end

        Book.where(id: duplicate_ids).delete_all
        canonical.reload.update!(**merged_attributes, isbn: group.key)
        refresh_import_counts!(affected_import_ids)
      end

      Outcome.new(group: group, status: :merged)
    end

    def merged_attributes(canonical, duplicates)
      sources = duplicates.sort_by { |book| -metadata_score(book) }
      attributes = {}
      MERGE_FIELDS.each do |field|
        next if canonical.public_send(field).present?

        value = sources.filter_map { |book| book.public_send(field).presence }.first
        attributes[field] = value if value
      end

      categories = [ canonical, *duplicates ].map(&:category)
      attributes[:category] = if categories.include?("classic")
        :classic
      elsif categories.include?("recommended")
        :recommended
      else
        :searched
      end
      attributes
    end

    def move_recommendations!(canonical, duplicate_ids)
      import_ids = []
      BookRecommendation.where(book_id: duplicate_ids).find_each do |recommendation|
        import_ids << recommendation.recommendation_import_id
        existing = BookRecommendation.find_by(
          recommendation_import_id: recommendation.recommendation_import_id,
          book_id: canonical.id
        )
        if existing
          recommendation.delete
        else
          recommendation.update!(book_id: canonical.id)
        end
      end
      import_ids.uniq
    end

    def move_game_plays!(canonical, duplicate_ids)
      GamePlay.where(book_id: duplicate_ids).find_each do |game_play|
        existing = GamePlay.find_by(
          user_id: game_play.user_id,
          game_type: game_play.game_type,
          book_id: canonical.id,
          played_on: game_play.played_on
        )
        if existing
          game_play.delete
        else
          game_play.update!(book_id: canonical.id)
        end
      end
    end

    def refresh_import_counts!(import_ids)
      RecommendationImport.where(id: import_ids).find_each do |recommendation_import|
        recommendation_import.update_columns(
          item_count: recommendation_import.book_recommendations.count,
          updated_at: Time.current
        )
      end
    end
  end
end
