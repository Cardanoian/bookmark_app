# 뒷이야기 이어쓰기(sequel, 게임 재구성 Phase 2). 책이 끝난 뒤 이어질 이야기를 학생이 창작하고
# 또래가 공감(👍)한다. 경계는 학급(classroom) — 정책이 같은 학급 뒷이야기만 열람·공감하게 강제한다.
# book_intros 스키마 미러 + AI 격려 코멘트 컬럼(ai_comment·ai_status) — Report ai_status enum 미러.
# 콘텐츠 소스가 학생 상상이라 본문 불필요·모든 책에서 항상 가능(가용성 게이트 대상 아님).
class CreateBookSequels < ActiveRecord::Migration[8.1]
  def change
    create_table :book_sequels do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.references :classroom, null: false, foreign_key: true
      t.text :body, null: false
      t.integer :votes_count, null: false, default: 0
      # 학생 글을 평가한 Gemini(또는 무API 규칙기반 폴백)의 격려형 코멘트. 작성자 본인에게만 노출.
      t.text :ai_comment
      # 비동기 AI 코멘트 상태(pending=0/processing=1/done=2/failed=3, Report ai_status 미러).
      t.integer :ai_status, null: false, default: 0

      t.timestamps
    end

    add_index :book_sequels, [ :book_id, :classroom_id ]
    add_index :book_sequels, :votes_count
  end
end
