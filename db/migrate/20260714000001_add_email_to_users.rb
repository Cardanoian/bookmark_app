# 교직원(교사·관리자·사서) 로그인 분리(이메일·비밀번호)를 위한 email 컬럼 추가.
# 학생은 (학교·학급·이름) 튜플로 로그인하므로 email 이 없다 → nullable.
# SQLite 유니크 인덱스는 NULL 다중 허용이라 학생 다수의 email=NULL 이 충돌하지 않는다.
# 저장 전 소문자 정규화(user.rb)하므로 대소문자 무관 유일성이 인덱스만으로 보장된다.
class AddEmailToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email, :string
    add_index :users, :email, unique: true
  end
end
