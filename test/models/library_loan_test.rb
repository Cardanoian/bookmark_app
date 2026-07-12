require "test_helper"

# 인기대출 레코드(#5 미테스트 모델 보강). source enum·검증·전국/학교 집계 경계.
class LibraryLoanTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "대출학교")
  end

  test "source enum defines csv and data4library with csv default" do
    assert_equal({ "csv" => 0, "data4library" => 1 }, LibraryLoan.sources)
    assert LibraryLoan.new.csv?, "기본 source 는 csv"
  end

  test "book_title is required" do
    loan = LibraryLoan.new(count: 3)
    assert_not loan.valid?
    assert loan.errors[:book_title].any?
  end

  test "count must be non-negative" do
    assert_not LibraryLoan.new(book_title: "책", count: -1).valid?
    assert LibraryLoan.new(book_title: "책", count: 0).valid?
  end

  test "school is optional so a nil school_id means a national aggregate" do
    national = LibraryLoan.create!(book_title: "전국책", count: 100, source: :data4library)
    assert_nil national.school
    scoped = LibraryLoan.create!(book_title: "학교책", count: 5, school: @school)
    assert_equal @school, scoped.school
  end
end
