# 학생별 AI 활용 동의 + 개인정보 동의 기록(P1-1). 보호자 동의(교사가 기록) 없는 학생의
# 데이터를 외부 AI(Gemini)로 보내지 않도록 게이팅하는 상태를 users 에 둔다.
#   ai_consent            = AI 활용 동의(옵트인 boolean, 기본 false → 미동의 시 규칙기반 폴백)
#   ai_consent_at         = 동의/철회 매 변경 시각(감사)
#   ai_consent_recorded_by_id = 동의를 기록한 교사(감사, 교사 삭제 시 nullify)
#   privacy_consent_at    = §1 개인정보 필수동의 수령 시각(계정 생성 시 스탬프)
# 기존 학생은 ai_consent=false(옵트인) + privacy_consent_at=nil(미기록 정직값)로 남는다.
class AddAiConsentToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :ai_consent, :boolean, null: false, default: false
    add_column :users, :ai_consent_at, :datetime
    add_column :users, :privacy_consent_at, :datetime
    add_reference :users, :ai_consent_recorded_by, null: true, index: true,
                  foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
