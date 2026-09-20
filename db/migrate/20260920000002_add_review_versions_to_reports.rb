# 독후감 첨삭에 **제출 버전**을 붙인다(BUG_FIX_PLAN F2·F3).
#
# 배경(결함): AiReviewJob 에 "어느 제출의 첨삭인가"가 없어, 학생이 고쳐 다시 낸 뒤에 늦게 끝난 이전
# 작업이 새 본문에 이전 첨삭을 덮어썼고(겹쳐 돈 작업이 저마다 포인트를 전액 적립), 첨삭이 만들어지기 전에
# 승인된 글은 첨삭이 저장되는 순간 교사가 읽지 않은 채 학생에게 공개됐다.
#
#   review_version           : 현재 첨삭 요청의 버전. 제출·재제출마다 1 증가(초안은 0).
#   completed_review_version : 결과 저장과 포인트 반영을 마친 버전(없으면 NULL).
#
# `updated_at` 은 승인·자동 저장에도 바뀌고 `submitted_at` 은 "처음 낸 시각"이라는 뜻을 지켜야 해서
# 둘 다 버전으로 쓸 수 없다. 인덱스는 두지 않는다 — 이 컬럼들은 항상 id 로 좁힌 뒤의 술어로만 읽힌다.
class AddReviewVersionsToReports < ActiveRecord::Migration[8.1]
  AI_STATUS_DONE = 2 # Report.ai_statuses[:done] — 모델 enum 에 기대지 않게 정수로 적는다.

  def up
    add_column :reports, :review_version, :integer, null: false, default: 0
    add_column :reports, :completed_review_version, :integer

    # 기존 행 백필(§7.1). 본문·첨삭·포인트·경험치는 다시 계산하지 않고, updated_at 도 건드리지 않는다
    # (백필은 사용자 행동이 아니다 — 20260728000003 선례. updated_at 은 초안의 draft_version 이기도 하다).
    #  · 미제출 초안            → 0 / NULL (기본값 그대로)
    #  · 제출된 글              → review_version 1
    #  · 그중 done + 루브릭 있음 → completed_review_version 1
    #  · 대기·처리 중·실패      → 완료 버전 NULL. 예전 루브릭이 남아 있어도 지금 결과가 완성됐다고 보지 않는다.
    execute "UPDATE reports SET review_version = 1 WHERE submitted_at IS NOT NULL"
    execute <<~SQL.squish
      UPDATE reports SET completed_review_version = 1
      WHERE submitted_at IS NOT NULL
        AND ai_status = #{AI_STATUS_DONE}
        AND rubric IS NOT NULL AND rubric NOT IN ('{}', '[]', 'null', '')
    SQL
  end

  def down
    remove_column :reports, :completed_review_version
    remove_column :reports, :review_version
  end
end
