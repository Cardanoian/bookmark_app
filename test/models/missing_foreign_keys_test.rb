require "test_helper"

# §2.5 마이그레이션(AddMissingForeignKeys)이 추가하는 선택적 FK 가 스키마에 존재하는지
# 검증한다. 이 테스트는 리드가 db:migrate 를 실행해 스키마에 FK 가 반영된 뒤 green 이 된다
# (up/down 왕복·고아행 정리·on_delete: :nullify 는 격리된 DB 로 별도 검증 완료).
class MissingForeignKeysTest < ActiveSupport::TestCase
  EXPECTED = [
    [ :challenges, :schools, :school_id ],
    [ :challenges, :books, :book_id ],
    [ :topics, :classrooms, :classroom_id ],
    [ :topics, :schools, :school_id ],
    [ :topics, :books, :book_id ],
    [ :library_events, :schools, :school_id ],
    [ :library_events, :books, :book_id ],
    [ :seasons, :schools, :school_id ],
    [ :quizzes, :books, :book_id ],
    [ :quizzes, :classrooms, :classroom_id ],
    # [ :missions, :books, :book_id ] — menu_refactor 심화 PR6 에서 드롭(레거시 미션 지정 도서 컬럼)
    [ :library_loans, :schools, :school_id ]
  ].freeze

  test "every missing foreign key is present in the schema" do
    conn = ActiveRecord::Base.connection
    EXPECTED.each do |from, to, column|
      assert conn.foreign_key_exists?(from, to, column: column),
             "#{from}.#{column} -> #{to} FK 가 있어야 한다"
    end
  end
end
