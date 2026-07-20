# 학생 홈(menu_refactor 심화 §2.D.3·§5.1) — 발견·현재 미션 요약 읽기 전용 조회.
# 전체 기록을 홈에 복제하지 않는다. 각 섹션은 제한된 수량만 렌더하고 독립적으로 폴백한다.
class StudentHomeQuery
  BOOK_LIMIT = 6

  # 인기 도서 후보 풀 상한(= "다른 책 보기" 5페이지분). 학급 30일치라 실측은 훨씬 작지만
  # 상한 없는 집계는 두지 않는다.
  POPULAR_POOL_LIMIT = BOOK_LIMIT * 5

  MAX_CYCLE = 10_000

  def initialize(user, discovery_cycle: 0, recommend_cycle: 0, popular_cycle: 0)
    @user = user
    @discovery_cycle = discovery_cycle.to_i.clamp(0, MAX_CYCLE)
    @recommend_cycle = recommend_cycle.to_i.clamp(0, MAX_CYCLE)
    @popular_cycle = popular_cycle.to_i.clamp(0, MAX_CYCLE)
  end

  # 공식 추천도서: 총괄관리자가 마지막으로 활성화한 엑셀의 어린이 분과 중 아직 활동하지 않은 책.
  # 가나다순 원본이 매일 같은 앞 6권만 노출되지 않도록 날짜를 시작점으로 결정적으로 회전하고,
  # "다른 책 보기"(recommend cycle)를 누를 때마다 다음 6권으로 순환한다(발견 섹션과 동형).
  def recommended_books
    return @recommended_books if defined?(@recommended_books)

    ids = recommended_book_ids
    return @recommended_books = Book.none if ids.empty?

    offset = ((Date.current.jd + @recommend_cycle) * BOOK_LIMIT) % ids.length
    selected_ids = ids.rotate(offset).first(BOOK_LIMIT)
    books = Book.where(id: selected_ids).index_by(&:id)
    @recommended_books = selected_ids.filter_map { |id| books[id] }
  end

  # 추천도서가 한 화면(BOOK_LIMIT)보다 많을 때만 "다른 책 보기"가 의미를 가진다.
  def more_recommended_books?
    recommended_book_ids.length > BOOK_LIMIT
  end

  def next_recommend_cycle
    @recommend_cycle >= MAX_CYCLE ? 0 : @recommend_cycle + 1
  end

  # 책 발견: 학생·날짜별 시작점을 기본값으로 삼고 "다른 책 보기"를 누를 때마다 다음 6권으로
  # 순환한다. SQL RANDOM 대신 offset+고정 title 순을 써서 큰 카탈로그에서도 재현 가능하게 한다.
  def discovery_books
    return @discovery_books if defined?(@discovery_books)

    scope = Book.where(category: [ Book.categories[:recommended], Book.categories[:classic] ])
                .where.not(id: active_book_ids)
    if (recommendation_import = RecommendationImport.current)
      scope = scope.where.not(id: recommendation_import.book_recommendations.select(:book_id))
    end
    ordered = scope.order(:title, :id)
    total = ordered.count
    return @discovery_books = Book.none if total.zero?

    offset = discovery_offset(total)
    books = ordered.offset(offset).limit(BOOK_LIMIT).to_a
    if books.size < BOOK_LIMIT
      books.concat(ordered.where.not(id: books.map(&:id)).limit(BOOK_LIMIT - books.size).to_a)
    end
    @discovery_books = books
  end

  def next_discovery_cycle
    @discovery_cycle >= MAX_CYCLE ? 0 : @discovery_cycle + 1
  end

  # 인기 도서(v1): 같은 학급 최근 30일 승인 독후감의 book_id 집계 상위.
  # 추천도서와 달리 날짜를 시작점에 더하지 않는다 — 인기 도서는 순위 자체가 정보이므로
  # cycle 0 은 언제나 실제 1~6위를 보여주고, "다른 책 보기"(popular cycle)로만 다음 6권씩 순환한다.
  def popular_books
    return @popular_books if defined?(@popular_books)

    ids = popular_book_ids
    return @popular_books = Book.none if ids.empty?

    offset = (@popular_cycle * BOOK_LIMIT) % ids.length
    selected_ids = ids.rotate(offset).first(BOOK_LIMIT)
    books = Book.where(id: selected_ids).index_by(&:id)
    @popular_books = selected_ids.filter_map { |id| books[id] }
  end

  # 인기 도서 후보가 한 화면(BOOK_LIMIT)보다 많을 때만 "다른 책 보기"가 의미를 가진다.
  def more_popular_books?
    popular_book_ids.length > BOOK_LIMIT
  end

  def next_popular_cycle
    @popular_cycle >= MAX_CYCLE ? 0 : @popular_cycle + 1
  end

  # 진행 중(active·published) 미션과 목표 진행도. 현재 학생 한 명이라 단건 계산 허용(§11.3).
  # [{ mission:, progress: { completed:, goals: [...] }, participation: }]
  def active_missions
    participations = @user.mission_participations
                          .joins(:mission).merge(Mission.published)
                          .where("missions.start_date <= :d AND missions.end_date >= :d", d: Date.current)
                          .includes(mission: { mission_goals: :book })
    participations.map do |participation|
      mission = participation.mission
      {
        mission: mission,
        participation: participation,
        progress: Missions::ProgressCalculator.new(mission, @user, participation: participation).call
      }
    end
  end

  # 우리 반·우리 학교 최근 토론방(홈 진입점). TopicPolicy::Scope 의 학생 규칙을 그대로 미러해
  # 경계를 지킨다(학생은 classroom_id·school_id 를 항상 가짐). 숨김 토픽은 visible 로 배제.
  def recent_topics(limit: 4)
    base = Topic.visible
    classroom_scope = base.where(scope: :classroom, classroom_id: @user.classroom_id)
    school_scope = base.where(scope: :school, school_id: @user.school_id)
    classroom_scope.or(school_scope).includes(:book).order(created_at: :desc).limit(limit).to_a
  end

  private

  # 활성 XLSX 추천 중 아직 활동하지 않은 book_id(position 순). recommended_books·more_recommended_books? 공용.
  def recommended_book_ids
    @recommended_book_ids ||= begin
      recommendation_import = RecommendationImport.current
      if recommendation_import
        recommendation_import.book_recommendations
                             .where.not(book_id: active_book_ids)
                             .order(:position).pluck(:book_id)
      else
        []
      end
    end
  end

  # 같은 학급 최근 30일 승인 독후감의 book_id 집계 상위(순위 순). popular_books·more_popular_books? 공용.
  # COUNT 동점의 SQLite 비결정 순서는 페이징에서 같은 책이 두 페이지에 나오거나 사라지게 하므로
  # book_id 로 타이브레이크해 회전을 결정적으로 만든다.
  def popular_book_ids
    @popular_book_ids ||= begin
      classroom_id = @user.classroom_id
      if classroom_id
        Report.where(classroom_id: classroom_id, reviewed: true)
              .where.not(book_id: nil)
              .where(created_at: 30.days.ago..)
              .group(:book_id)
              .order(Arel.sql("COUNT(*) DESC, book_id ASC"))
              .limit(POPULAR_POOL_LIMIT)
              .count.keys
      else
        []
      end
    end
  end

  def discovery_offset(total)
    seed = Date.current.jd + @user.id.to_i
    ((seed + @discovery_cycle) * BOOK_LIMIT) % total
  end

  # 이미 활동(독후감·게임)한 책 id — 공식 추천과 책 발견 목록에서 제외한다.
  def active_book_ids
    @active_book_ids ||= (@user.reports.where.not(book_id: nil).distinct.pluck(:book_id) +
                          @user.game_plays.where.not(book_id: nil).distinct.pluck(:book_id)).uniq
  end
end
