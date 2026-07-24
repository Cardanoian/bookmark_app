# 모든 Book을 특정 판본의 ISBN-13으로 식별한다. 이 마이그레이션 전에 운영 태스크로 공란 도서를
# 보강·병합해야 하며, 남아 있으면 데이터 손실 대신 명시적으로 중단한다.
class EnforceBooksIsbn < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  CHECK_NAME = "chk_books_isbn13_format"

  def up
    invalid_count = select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM books
      WHERE isbn IS NULL OR isbn = '' OR length(isbn) != 13 OR isbn GLOB '*[^0-9]*'
    SQL
    if invalid_count.positive?
      raise ActiveRecord::MigrationError,
            "books에 ISBN-13이 아닌 행이 #{invalid_count}개 있습니다. " \
            "books:deduplicate_isbn 및 books:enrich로 먼저 정리하세요."
    end

    # SQLite는 NOT NULL/CHECK 변경 시 books 테이블을 재빌드한다. 바깥 마이그레이션
    # 트랜잭션에서 PRAGMA foreign_keys를 끌 수 없으면 DROP TABLE이 자식 FK의
    # ON DELETE CASCADE/SET NULL을 실행한다. 트랜잭션을 끄고 전체 재빌드를 감싸
    # book_recommendations·quizzes 등 기존 참조를 그대로 보존한다.
    connection.disable_referential_integrity do
      remove_index :books, name: "index_books_on_isbn"
      change_column_null :books, :isbn, false
      add_check_constraint :books,
                           "length(isbn) = 13 AND isbn NOT GLOB '*[^0-9]*'",
                           name: CHECK_NAME
      add_index :books, :isbn, unique: true, name: "index_books_on_isbn"
    end
  end

  def down
    connection.disable_referential_integrity do
      remove_index :books, name: "index_books_on_isbn"
      remove_check_constraint :books, name: CHECK_NAME
      change_column_null :books, :isbn, true
      add_index :books, :isbn, unique: true,
                where: "isbn IS NOT NULL AND isbn != ''",
                name: "index_books_on_isbn"
    end
  end
end
