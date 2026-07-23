class RemoveModeFromUsers < ActiveRecord::Migration[8.1]
  def change
    # normal/easy 는 실제 동작에 연결되지 않은 휴면 enum 이었다. 되돌릴 때는 모든 사용자를
    # normal(0)로 복원하며, 사용되지 않던 과거 easy 값은 의도적으로 복구하지 않는다.
    remove_column :users, :mode, :integer, default: 0, null: false
  end
end
