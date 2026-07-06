# 인기대출 집계(P6.5, RAILS_PLAN §6.2). 정보나루 API 또는 교육청 DLS CSV 업로드로 채운다.
# school_id 는 nullable — 전국 집계는 NULL(사서 대시보드에서 "학교 + 전국" 을 함께 노출).
class CreateLibraryLoans < ActiveRecord::Migration[8.1]
  def change
    create_table :library_loans do |t|
      t.integer :school_id
      t.string :book_title
      t.string :isbn
      t.integer :count, null: false, default: 0
      t.integer :source, null: false, default: 0
      t.string :period

      t.timestamps
    end

    add_index :library_loans, :school_id
    add_index :library_loans, [ :school_id, :book_title, :period ]
  end
end
