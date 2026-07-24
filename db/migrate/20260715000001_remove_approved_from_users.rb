# 교사 자가가입 승인 게이트 제거. 교사는 가입 즉시 활동할 수 있게 되어 approved 컬럼과
# 관련 게이트(application_controller·sessions_controller·admin/users)를 함께 없앤다.
# down 은 컬럼을 되살리고 기존 사용자를 모두 승인(true) 처리해 회귀 없이 복구한다.
class RemoveApprovedFromUsers < ActiveRecord::Migration[8.1]
  def up
    remove_column :users, :approved
  end

  def down
    add_column :users, :approved, :boolean, default: false, null: false
    execute("UPDATE users SET approved = 1")
  end
end
