class AddClassroomForeignKeyToUsers < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :users, :classrooms
  end
end
