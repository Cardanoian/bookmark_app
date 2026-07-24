class MakeBooksIsbnIndexUnique < ActiveRecord::Migration[8.1]
  # 동시 동일-isbn 신규 등록(검색 캐시 upsert · 제출 시 register)을 DB 레벨에서 차단하기
  # 위해 기존 비유니크 `index_books_on_isbn` 를 부분 유니크 인덱스로 교체한다.
  # blank/NULL isbn(텍스트-only 제목 도서)은 술어(WHERE)로 제약 밖 → 다건 공존 허용.
  # dev DB 중복 isbn 0건 확인 — 파괴적 dedup 없이 인덱스만 교체한다(완전 가역).
  def up
    remove_index :books, name: "index_books_on_isbn"
    add_index :books, :isbn, unique: true,
              where: "isbn IS NOT NULL AND isbn != ''",
              name: "index_books_on_isbn"
  end

  def down
    remove_index :books, name: "index_books_on_isbn"
    add_index :books, :isbn, name: "index_books_on_isbn"
  end
end
