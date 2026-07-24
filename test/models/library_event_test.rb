require "test_helper"

# 이달의 책·행사(#5 미테스트 모델 보강). 학교 소속 필수·도서 선택·title 검증.
class LibraryEventTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "행사학교")
    @book = Book.create!(title: "행사도서", category: :recommended)
  end

  test "title is required" do
    event = LibraryEvent.new(school: @school)
    assert_not event.valid?
    assert event.errors[:title].any?
  end

  test "belongs to a school and an optional book" do
    event = LibraryEvent.create!(school: @school, title: "이달의 책")
    assert_equal @school, event.school
    assert_nil event.book

    with_book = LibraryEvent.create!(school: @school, title: "북토크", book: @book)
    assert_equal @book, with_book.book
  end

  test "requires a school (not optional)" do
    event = LibraryEvent.new(title: "학교없는행사")
    assert_not event.valid?
    assert event.errors[:school].any?
  end
end
