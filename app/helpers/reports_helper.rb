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
  #
  # **미제출 초안(draft?)은 done 판정보다 앞에 둔다.** OCR 초안은 판독을 마치면 ai_status done
  # 이라, 제출 여부를 보지 않으면 아직 내지도 않은 글이 "선생님 확인 중"으로 표시된다 — 학생은
  # 그 말을 믿고 제출하기를 누르지 않고, 첨삭은 영영 붙지 않는다. failed 는 초안이든 제출본이든
  # 재시도가 유일한 다음 행동이라 그대로 앞에 남긴다(OCR 판독 실패 = 다시 찍기).
  def student_status_badge(report)
    label, variant =
      if report.reviewed?
        [ "확인 완료", "badge-success" ]
      elsif report.ai_status == "failed"
        [ "다시 시도", "badge-danger" ]
      elsif report.draft? && report.ocr?
        # 사진 초안은 학생이 "저장"한 것이 아니라 **업로드 순간 서버가 만든** 레코드다
        # (비동기 판독 결과를 받을 자리가 필요해서). 키보드 초안과 같은 "작성 중"으로 뭉개면
        # 아이는 자기가 임시 저장한 줄 알고 제출하기를 누르지 않아 첨삭이 영영 안 붙는다.
        if report.pending? || report.processing?
          [ "사진 읽는 중", "badge-yellow" ]
        else
          [ "제출 전 확인", "badge-neutral" ]
        end
      elsif report.draft?
        [ "작성 중", "badge-neutral" ]
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
