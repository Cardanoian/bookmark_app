# 챌린지 소개글(선택 입력, 미션 description 과 대칭). 학생에게 보여줄 안내 문구를 담는다.
# nullable·default 없음 — 미션처럼 무검증 선택 입력이라 빈 값을 허용한다.
class AddDescriptionToChallenges < ActiveRecord::Migration[8.1]
  def change
    add_column :challenges, :description, :text
  end
end
