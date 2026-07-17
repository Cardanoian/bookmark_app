module ReportsHelper
  AI_STATUS_LABELS = {
    "pending" => [ "첨삭 대기", "badge-neutral" ],
    "processing" => [ "첨삭 중", "badge-yellow" ],
    "done" => [ "첨삭 완료", "badge-success" ],
    "failed" => [ "첨삭 실패", "badge-danger" ]
  }.freeze

  LEVEL_COLORS = {
    "A" => "bg-brand-yellow text-ink",
    "B" => "bg-brand-blue text-white",
    "C" => "bg-hairline text-slate"
  }.freeze

  def ai_status_badge(report)
    label, variant = AI_STATUS_LABELS.fetch(report.ai_status, [ report.ai_status, "badge-neutral" ])
    content_tag :span, label, class: "badge #{variant}"
  end

  def level_badge(level)
    return if level.blank?

    classes = LEVEL_COLORS.fetch(level, "bg-hairline text-slate")
    content_tag :span, level, class: "inline-flex h-7 w-7 items-center justify-center rounded-full text-sm font-bold #{classes}"
  end

  def axis_label(axis)
    ReadingDomain::AXIS_LABELS[axis.to_sym]
  end
end
