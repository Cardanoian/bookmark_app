# 교사 자가가입 승인 게이트(0.1). 신규 가입 교사는 approved:false 로 생성되어
# 관리자 승인 전에는 로그인할 수 없다. 마이그레이션 시점의 기존 사용자는 시드·데모 등
# 사전 신뢰 계정이므로 모두 승인(true) 처리해 회귀를 막는다.
class AddApprovedToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :approved, :boolean, default: false, null: false
    # 앱 모델(User) 대신 raw SQL 로 백필해 마이그레이션을 모델 스코프(향후 default_scope 등)와
    # 분리한다 — 새 DB 에서 재실행해도 결정적으로 전 행을 승인 처리한다.
    execute("UPDATE users SET approved = 1")
  end

  def down
    remove_column :users, :approved
  end
end
