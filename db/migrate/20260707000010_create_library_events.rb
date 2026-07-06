# 이달의 책·행사(P6.5). 사서가 학교 단위로 등록하는 도서관 행사·추천 도서.
class CreateLibraryEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :library_events do |t|
      t.integer :school_id
      t.string :title
      t.text :description
      t.date :event_on
      t.integer :book_id

      t.timestamps
    end

    add_index :library_events, :school_id
  end
end
