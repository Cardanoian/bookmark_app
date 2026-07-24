# 교사 대시보드(P6.1). 담임 학급의 독후감 통계·5축 평균·약점 인사이트·검토 큐 요약.
class Teacher::DashboardsController < Teacher::BaseController
  def show
    @classrooms = teacher_classrooms.order(:grade, :class_no).to_a
    classroom_ids = @classrooms.map(&:id)
    # 전체 리포트 본문을 메모리에 적재하지 않는다. 단순 집계는 SQL COUNT/SUM 으로,
    # 5축 평균은 rubric 컬럼만 적재(본문 제외)해 계산한다(§3.4, 성능E).
    reports = Report.where(classroom_id: classroom_ids)
    @students = User.where(classroom_id: classroom_ids, role: :student)

    @total_reports = reports.count
    @pending_count = reports.where(reviewed: false).count
    @a_ratio = a_ratio(reports)
    @avg_points = @students.average(:points).to_f.round(1)
    @avg_experience = @students.average(:experience).to_f.round(1)

    @axis_averages = axis_averages(reports) # Relation → SQL 집계(본문·행 미적재)
    @axis_labels = ReadingDomain::RUBRIC_AXES.map { |axis| ReadingDomain::AXIS_LABELS[axis] }
    @weakness = weakness_insight(@axis_averages, dashboard_band(@classrooms))
    @improvement_avg = improvement_summary(reports)
    @review_queue = reports.where(reviewed: false).where.not(rubric: nil)
                           .includes(:user, :book).order(:created_at).limit(5).to_a

    # 무게이트 롤아웃 사후 검토(교사 알림): 담임 학급 학생이 신고한 온디맨드 게임 콘텐츠 최근 목록.
    # 신고 2건이면 자동 숨김+재생성되지만, 1건만 있어도 교사가 콘텐츠 품질을 사후 점검하도록 노출한다.
    @reported_content = QuizReport.where(user_id: @students.select(:id))
                                  .includes(:user, quiz: :book)
                                  .order(created_at: :desc).limit(10).to_a

    # 신고된 토론 글(reading_discussion 사후 검토): **저자(작성자)가 담임 학급 소속**인 글만 노출한다
    # (신고자 학급이 아니라 저자 학급 기준 — 담임이 자기 학생의 글을 모더레이션하는 권한과 정합).
    # 자동 숨김이 없으므로 1건이라도 신고되면 교사가 직접 확인·숨김하도록 노출한다.
    @reported_forum_posts = ForumPost.where(user_id: @students.select(:id))
                                     .where("forum_posts.reports_count > 0")
                                     .includes(:user, :topic)
                                     .order(reports_count: :desc, created_at: :desc).limit(10).to_a

    # 학생 기여 문제 검토 큐(전국 공유 문제은행 §4.3): 담임 학급 학생들의 pending 기여 건수.
    # 승인하면 전국 공유 풀로 물질화되므로 정확성·연령 적합성을 함께 검토한다.
    @pending_contributions_count = QuizContribution.pending.where(user_id: @students.select(:id)).count
  end

  private

  # A등급 비율(%). 채점된(level 있는) 독후감 기준. 로우 적재 없이 SQL COUNT 로 집계.
  def a_ratio(reports)
    scored = reports.where.not(level: [ nil, "" ]).count
    return 0 if scored.zero?

    (reports.where(level: "A").count * 100.0 / scored).round
  end

  # 담당 학급 집합에서 대표 학년군(band)을 파생. 단일 밴드면 그 밴드로 약점 인사이트의
  # 성취기준·추천활동을 학생 눈높이에 맞춘다. 여러 밴드가 섞이면(총괄=Classroom.all,
  # 교차-밴드 겸임 담임) g56 기본으로 폴백한다 — 이는 전교 통계(school_admin)와 동일한
  # "종착 밴드" 관례(교사·집계 대면)이며, game_band_for/guided_band_for/discovery_band_for
  # 의 g12 age-safety 폴백(아동 대면, 너무 어려운 콘텐츠 노출 차단 목적)과는 방향이 의도적으로
  # 다르다. 학년→밴드로 접은 뒤 uniq 하므로 3+4학년(교차 학년도) 겸임은 둘 다 g34 로 수렴한다.
  def dashboard_band(classrooms)
    bands = classrooms.map { |classroom| ReadingDomain.band_for(classroom.grade) }.uniq
    bands.one? ? bands.first : ReadingDomain::DEFAULT_BAND
  end

  # 가장 낮은 5축 → 추천 활동 + 성취기준 코드(학급 학년군 눈높이).
  def weakness_insight(averages, band)
    return nil if averages.values.all?(&:zero?)

    axis, score = averages.min_by { |_, value| value }
    {
      axis: axis,
      label: ReadingDomain::AXIS_LABELS[axis],
      score: score,
      standard: ReadingDomain.achievement_standards(band)[axis],
      activity: ReadingDomain.recommended_activities(band)[axis]
    }
  end

  # 고쳐쓰기 향상도 평균(improvement 기록된 것만). 로우 적재 없이 SQL COUNT/SUM 으로 집계.
  def improvement_summary(reports)
    scoped = reports.where.not(improvement: nil)
    count = scoped.count
    return nil if count.zero?

    (scoped.sum(:improvement) / count).round(2)
  end
end
