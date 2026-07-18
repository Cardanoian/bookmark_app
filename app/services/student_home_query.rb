# 학생 홈(menu_refactor 심화 §2.D.3·§5.1) — 발견·이어하기·현재 미션 요약 읽기 전용 조회.
# 전체 기록을 홈에 복제하지 않는다. 각 섹션은 제한된 수량만 렌더하고 독립적으로 폴백한다.
class StudentHomeQuery
  BOOK_LIMIT = 6

  def initialize(user)
    @user = user
  end

  # 추천 도서(v1): 추천·고전 중 아직 활동 안 한 책을 결정적(title) 순으로. 무작위 SQL 미사용.
  # 학년군 개인화(grade_band)는 후속. 결과 부족 시 전체 추천/고전으로 보충된다.
  def recommended_books
    Book.where(category: [ Book.categories[:recommended], Book.categories[:classic] ])
        .where.not(id: active_book_ids)
        .order(:title)
        .limit(BOOK_LIMIT)
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

  private

  # 이미 활동(독후감·게임)한 책 id — 추천에서 뒤로 뺀다.
  def active_book_ids
    @active_book_ids ||= (@user.reports.where.not(book_id: nil).distinct.pluck(:book_id) +
                          @user.game_plays.where.not(book_id: nil).distinct.pluck(:book_id)).uniq
  end
end
