class StudentGrowthTimeline
  LIMIT = 12
  Entry = Data.define(:report, :scores, :average) do
    # 이 글을 낸 시각(= 시계열의 시간축). 레거시 행은 created_at 폴백. 화면의 날짜도 이 값을 쓴다 —
    # 정렬과 표시가 다른 시각을 쓰면 "시간순" 목록의 날짜가 뒤섞여 보인다.
    def submitted_at
      report.submitted_at || report.created_at
    end
  end

  attr_reader :entries, :approved_report_count

  def initialize(user)
    @user = user
    scope = user.reports.where(reviewed: true)
    @approved_report_count = scope.count
    @entries = build_entries(scope)
  end

  def latest
    entries.last
  end

  def previous
    entries[-2]
  end

  def changes
    return empty_changes unless latest && previous

    ReadingDomain::RUBRIC_AXES.index_with do |axis|
      latest.scores.fetch(axis) - previous.scores.fetch(axis)
    end
  end

  def strongest_growth_axis
    positive = changes.select { |_axis, change| change.positive? }
    positive.max_by { |_axis, change| change }
  end

  private

  # 최근 12편을 **제출 순**으로 고른다. created_at(자동 저장의 첫 저장 시각) 순이면 먼저 쓰기 시작해
  # 나중에 낸 글이 '지난 글'로 밀려 "최근 글과 지난 글 비교"·가장 많이 오른 축이 뒤집힌다.
  def build_entries(scope)
    scope.where.not(rubric: nil)
         .includes(:book)
         .order(Arel.sql("COALESCE(reports.submitted_at, reports.created_at) DESC"), Report.arel_table[:id].desc)
         .limit(LIMIT)
         .to_a
         .select { |report| report.rubric.present? }
         .reverse
         .map do |report|
      Entry.new(report: report, scores: report.final_rubric_scores, average: report.final_average)
    end
  end

  def empty_changes
    ReadingDomain::RUBRIC_AXES.index_with { 0 }
  end
end
