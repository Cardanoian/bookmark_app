# 큐레이션 게임 문항 저장 테이블(Stage 2). db/seeds/book_quizzes.yml(Sonnet 팀 검수 문항)을
# books:seed_quizzes 로 물질화해 담는다. 큐레이션이 있는 책은 학생에게 이 검수 문항이 출제되고
# (ContentProvider 가 밴드별 지연 물질화·서빙), 제네릭 오프라인/미검증 AI로 덮이지 않는다.
#   content_axis : CuratedQuiz 전용 정수 매핑(mcq=0 / hint_reveal=1). Quiz enum 과 무관(독립).
#   payload      : 그 축의 문항 배열(YAML 원본 형태). set_for 가 균일 문항 해시로 변환한다.
# (book_id, content_axis) UNIQUE 로 축당 1행(멱등 upsert). 도서 삭제 시 함께 정리(cascade).
class CreateCuratedQuizzes < ActiveRecord::Migration[8.1]
  def change
    create_table :curated_quizzes do |t|
      t.references :book, null: false, foreign_key: { on_delete: :cascade }
      t.integer :content_axis, null: false
      t.json :payload, null: false
      t.timestamps
    end
    add_index :curated_quizzes, [ :book_id, :content_axis ], unique: true
  end
end
