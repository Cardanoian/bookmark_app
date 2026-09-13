# 단계 학습 위저드(LearnController)의 진행을 세션 쿠키 밖으로 옮긴다(2026-09-13, docs/improve 통합정리 §5-1c
# "범위 밖으로 새로 드러난 것"). 다섯 단계 답을 쿠키(4KB)에 쌓던 때는 답을 합쳐 한글 약 750자만 돼도
# CookieOverflow 로 500 이 났다. 학생마다 한 행이라 한도가 없고, 다른 기기에서도 이어 한다.
#
# 계정 연동(Accounts::MergeService)은 placeholder 계정을 raw delete_all 로 지우므로 FK 는 CASCADE 다 —
# 쓰다 만 단계 학습은 병합 대상이 아니다(쿠키에 있던 때도 병합 확정의 reset_session 으로 사라지던 값이다).
class CreateLearnWizardProgresses < ActiveRecord::Migration[8.1]
  def change
    create_table :learn_wizard_progresses do |t|
      t.references :user, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.integer :step, null: false, default: 1
      t.json :answers, null: false, default: {}
      t.timestamps
    end
  end
end
