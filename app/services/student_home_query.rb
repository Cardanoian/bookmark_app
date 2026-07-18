# 학생 홈(menu_refactor 심화 §2.D.3·§5.1) — 발견·이어하기·현재 미션 요약 읽기 전용 조회.
# 전체 기록을 홈에 복제하지 않는다. 각 섹션은 제한된 수량만 렌더하고 독립적으로 폴백한다.
class StudentHomeQuery
  BOOK_LIMIT = 6

  MAX_DISCOVERY_CYCLE = 10_000

  def initialize(user, discovery_cycle: 0)
    @user = user
    @discovery_cycle = discovery_cycle.to_i.clamp(0, MAX_DISCOVERY_CYCLE)
  end

  # 공식 추천도서: 총괄관리자가 마지막으로 활성화한 엑셀의 어린이 분과 중 아직 활동하지 않은 책.
  # 가나다순 원본이 매일 같은 앞 6권만 노출되지 않도록 목록을 날짜 기준으로 결정적으로 회전한다.
  def recommended_books
    recommendation_import = RecommendationImport.current
    return Book.none unless recommendation_import

    ids = recommendation_import.book_recommendations
                               .where.not(book_id: active_book_ids)
                               .order(:position).pluck(:book_id)
    return Book.none if ids.empty?

    selected_ids = ids.rotate((Date.current.jd * BOOK_LIMIT) % ids.length).first(BOOK_LIMIT)
    books = Book.where(id: selected_ids).index_by(&:id)
    selected_ids.filter_map { |id| books[id] }
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
    @discovery_cycle >= MAX_DISCOVERY_CYCLE ? 0 : @discovery_cycle + 1
  end

  # 인기 도서(v1): 같은 학급 최근 30일 승인 독후감의 book_id 집계 상위. 학급 데이터 없으면 빈 결과.
  def popular_books
    classroom_id = @user.classroom_id
    return Book.none if classroom_id.nil?

    counts = Report.where(classroom_id: classroom_id, reviewed: true)
                   .where.not(book_id: nil)
                   .where(created_at: 30.days.ago..)
                   .group(:book_id).order(Arel.sql("COUNT(*) DESC")).limit(BOOK_LIMIT).count
    return Book.none if counts.empty?

    books = Book.where(id: counts.keys).index_by(&:id)
    counts.keys.filter_map { |id| books[id] }
  end

  # 이어하기: 가장 최근 독후감(작성/첨삭/승인 어느 상태든) 1건. 없으면 nil(뷰가 CTA 폴백).
  def continue_report
    @user.reports.order(created_at: :desc).first
  end

  # 진행 중(active·published) 미션과 목표 진행도. 현재 학생 한 명이라 단건 계산 허용(§11.3).
  # [{ mission:, progress: { completed:, goals: [...] }, participation: }]
  def active_missions
    participations = @user.mission_participations
                          .joins(:mission).merge(Mission.published)
                          .where("missions.start_date <= :d AND missions.end_date >= :d", d: Date.current)
                          .includes(mission: :mission_goals)
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
