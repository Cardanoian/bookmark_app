require "test_helper"
require Rails.root.join("db/migrate/20260722000003_promote_reviewed_searched_books.rb")

# 승격 백필 마이그레이션 전용 테스트. 승인-시점 승격 훅 도입 이전에 승인된 searched 도서를
# up 직접 실행으로 recommended 소급 승격하고, 승인 독후감이 없는 searched·비-searched 도서는
# 건드리지 않으며 재실행에 멱등임을 검증한다(backfill_squished_book_titles 관례). 데이터 전용(DDL 없음).
class PromoteReviewedSearchedBooksTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "승격학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "승격학생", password: "password")
  end

  test "up 은 승인 독후감이 붙은 searched 도서를 recommended 로 승격한다" do
    book = Book.create!(title: "검색 도서", isbn: "9791112114198", category: :searched)
    Report.create!(user: @student, classroom: @classroom, book: book, body: "본문", reviewed: true)

    PromoteReviewedSearchedBooks.new.up

    assert book.reload.recommended?
  end

  test "up 은 미승인·독후감 없는 searched 도서는 그대로 둔다" do
    unreviewed = Book.create!(title: "미승인 검색 도서", isbn: "9791112114198", category: :searched)
    Report.create!(user: @student, classroom: @classroom, book: unreviewed, body: "본문", reviewed: false)
    orphan = Book.create!(title: "독후감 없는 검색 도서", isbn: "9788986621136", category: :searched)

    PromoteReviewedSearchedBooks.new.up

    assert unreviewed.reload.searched?, "미승인 독후감만 있는 검색 도서는 승격 대상이 아니다"
    assert orphan.reload.searched?, "독후감이 없는 검색 도서는 승격 대상이 아니다"
  end

  test "up 은 비-searched 도서를 건드리지 않고 재실행에 멱등이다" do
    classic = Book.create!(title: "고전", isbn: "9791112114198", category: :classic)
    Report.create!(user: @student, classroom: @classroom, book: classic, body: "본문", reviewed: true)

    PromoteReviewedSearchedBooks.new.up
    PromoteReviewedSearchedBooks.new.up # 재실행해도 결과가 같아야 한다(멱등)

    assert classic.reload.classic?, "고전은 승인돼도 카테고리 불변"
  end

  test "down 은 성공 no-op 이다(비가역 승격)" do
    assert_nothing_raised { PromoteReviewedSearchedBooks.new.down }
  end
end
