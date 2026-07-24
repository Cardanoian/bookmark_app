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

  # 학생 뷰(_report_detail·_report) 전용 상태 배지. "첨삭 완료"처럼 결과 준비를 암시하지 않게
  # 교사 검토 단계를 드러낸다. reviewed 를 먼저 판정한다(승인된 리포트는 ai_status done 이므로).
  # 교사 뷰는 계속 ai_status_badge 를 쓴다.
  def student_status_badge(report)
    label, variant =
      if report.reviewed?
        [ "확인 완료", "badge-success" ]
      elsif report.ai_status == "failed"
        [ "다시 시도", "badge-danger" ]
      elsif report.ai_status == "done"
        [ "선생님 확인 중", "badge-yellow" ]
      else
        [ "첨삭 준비 중", "badge-neutral" ]
      end
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
