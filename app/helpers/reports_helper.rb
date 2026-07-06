module ReportsHelper
  AI_STATUS_LABELS = {
    "pending" => [ "첨삭 대기", "bg-gray-100 text-gray-600" ],
    "processing" => [ "첨삭 중", "bg-amber-100 text-amber-700" ],
    "done" => [ "첨삭 완료", "bg-emerald-100 text-emerald-700" ],
    "failed" => [ "첨삭 실패", "bg-rose-100 text-rose-700" ]
  }.freeze

  LEVEL_COLORS = {
    "A" => "bg-amber-400 text-white",
    "B" => "bg-sky-400 text-white",
    "C" => "bg-gray-300 text-gray-700"
  }.freeze

  def ai_status_badge(report)
    label, classes = AI_STATUS_LABELS.fetch(report.ai_status, [ report.ai_status, "bg-gray-100 text-gray-600" ])
    content_tag :span, label, class: "inline-block rounded-full px-2 py-0.5 text-xs font-medium #{classes}"
  end

  def level_badge(level)
    return if level.blank?

    classes = LEVEL_COLORS.fetch(level, "bg-gray-300 text-gray-700")
    content_tag :span, level, class: "inline-flex h-7 w-7 items-center justify-center rounded-full text-sm font-bold #{classes}"
  end

  def axis_label(axis)
    ReadingDomain::AXIS_LABELS[axis.to_sym]
  end
end
