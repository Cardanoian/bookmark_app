# 독후감 "제출됨"을 명시적 사실로 기록한다.
#
# 배경(결함): OCR(사진) 경로는 첨부를 붙이기 위해 학생이 제출하기 **전에** Report 를 영속화하고
# (`OcrController#create`), `OcrJob` 이 판독을 마치면 `ai_status: :done` 을 쓴다. 그런데
# `ai_status` 는 *AI 첨삭* 상태 컬럼이기도 해서, 미제출 초안이 `ai_status=done, reviewed=false`
# 라는 "첨삭 끝나고 승인만 남은 글"과 구별되지 않는 상태가 된다. 그 결과
#   ① 교사 검토 큐(`reviewed: false`)에 초안이 올라오고,
#   ② 교사가 승인하면 `reviewed=true` 인데 `rubric` 은 NULL → `feedback_visible?` 이 영구히 false
#      → 5축·첨삭·등급·포인트가 통째로 없는 독후감이 확정된다.
# 제출 여부를 AI 상태에서 **추론**한 것이 원인이므로, 별도 컬럼으로 분리한다.
#
# 인덱스는 두지 않는다 — 이 컬럼은 단독 조회 축이 아니라 항상 기존
# `index_reports_on_classroom_id_and_reviewed` 로 좁혀진 뒤의 술어로만 읽힌다.
class AddSubmittedAtToReports < ActiveRecord::Migration[8.1]
  def up
    add_column :reports, :submitted_at, :datetime

    # 기존 행 백필: 이 컬럼 이전의 글은 모두 "제출됨"으로 본다. NULL 로 두면 승인·집계가 끝난
    # 과거 독후감이 일제히 초안으로 뒤집혀 교사 목록·통계에서 사라진다.
    # update_all 이라 updated_at 은 갱신하지 않는다(백필은 사용자 행동이 아니다 — 선례:
    # 20260728000002 의 email_verified_at 백필).
    Report.update_all("submitted_at = created_at")

    # 그중 위 결함으로 태어난 **미제출 OCR 초안**만 다시 NULL 로 되돌린다. 판별식
    # `ai_status=done AND rubric 비어 있음` 은 초안에만 성립한다 — AiReviewJob 은 rubric 과
    # done 을 같은 save! 로 쓰고 실패 시 failed 로 가므로, 제출된 글이 이 조합에 걸리지 않는다.
    # (아직 pending 인 OCR 초안은 방금 제출된 글과 구별할 수 없어 제출됨으로 남긴다 — 기존
    # 동작 그대로라 회귀가 아니다.)
    Report.where(ai_status: :done, reviewed: false)
          .where("rubric IS NULL OR rubric = '{}'")
          .update_all(submitted_at: nil)
  end

  def down
    remove_column :reports, :submitted_at
  end
end
