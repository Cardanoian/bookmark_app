# 총괄관리자가 업로드한 추천도서 엑셀의 이력과 해당 시점의 도서 목록을 보존한다.
# 활성 import 는 부분 유니크 인덱스로 정확히 하나만 허용하며, 새 파일을 완전히 처리한 뒤
# 트랜잭션 안에서 교체하므로 파싱/저장 실패가 현재 학생 홈 목록을 훼손하지 않는다.
class CreateRecommendationImports < ActiveRecord::Migration[8.1]
  def change
    create_table :recommendation_imports do |t|
      t.string :filename, null: false
      t.string :file_digest, null: false
      t.string :source_title
      t.references :imported_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :imported_at, null: false
      t.integer :item_count, null: false, default: 0
      t.boolean :active, null: false, default: false

      t.timestamps
    end

    add_index :recommendation_imports, :file_digest, unique: true
    add_index :recommendation_imports, :active, unique: true, where: "active = 1",
              name: "index_recommendation_imports_one_active"

    create_table :book_recommendations do |t|
      t.references :recommendation_import, null: false, foreign_key: { on_delete: :cascade }
      t.references :book, null: false, foreign_key: { on_delete: :cascade }
      t.string :issue
      t.string :section, null: false
      t.date :published_on
      t.integer :position, null: false

      t.timestamps
    end

    add_index :book_recommendations, [ :recommendation_import_id, :book_id ],
              unique: true, name: "index_book_recommendations_import_book"
    add_index :book_recommendations, [ :recommendation_import_id, :position ],
              name: "index_book_recommendations_import_position"
  end
end
