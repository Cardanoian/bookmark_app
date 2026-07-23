class StudentGrowthTimeline
  LIMIT = 12
  Entry = Data.define(:report, :scores, :average)

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

  def build_entries(scope)
    scope.where.not(rubric: nil)
         .includes(:book)
         .order(created_at: :desc, id: :desc)
         .limit(LIMIT)
         .to_a
         .select { |report| report.rubric.present? }
         .reverse
         .map do |report|
      scores = report.final_rubric_scores
      average = (scores.values.sum.to_f / scores.size).round(1)
      Entry.new(report: report, scores: scores, average: average)
    end
  end

  def empty_changes
    ReadingDomain::RUBRIC_AXES.index_with { 0 }
  end
end
