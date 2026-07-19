require "test_helper"

# before_validation :normalize_book_title — 자유입력 책 제목의 앞뒤·중복 공백을 squish 하고
# 빈 문자열은 nil 로 만든다(index book_title 필터가 정규화 값 하나로 조회되게 한다).
class ReportBookTitleNormalizationTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "정규화초등학교")
    @classroom = Classroom.create!(school: @school, grade: 4, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "정규화학생", password: "password")
    @book = Book.create!(title: "정규화 책")
  end

  test "앞뒤 공백을 제거한다" do
    report = build_report(book_title: "  긴긴밤  ")
    assert report.save, report.errors.full_messages.to_sentence
    assert_equal "긴긴밤", report.book_title
  end

  test "중복 공백을 하나로 정리한다" do
    report = build_report(book_title: "이중  공백  제목")
    assert report.save, report.errors.full_messages.to_sentence
    assert_equal "이중 공백 제목", report.book_title
  end

  test "빈 문자열·공백만 있으면 nil 로 만든다" do
    report = Report.new(user: @user, classroom: @classroom, book: @book, book_title: "   ")
    assert report.save, report.errors.full_messages.to_sentence
    assert_nil report.book_title
  end

  test "정상 제목은 그대로 유지한다" do
    report = build_report(book_title: "마당을 나온 암탉")
    assert report.save, report.errors.full_messages.to_sentence
    assert_equal "마당을 나온 암탉", report.book_title
  end

  test "book_id 가 있으면 book_title 없이도 저장된다" do
    report = Report.new(user: @user, classroom: @classroom, book: @book, book_title: "  ", body: "본문")
    assert report.save, report.errors.full_messages.to_sentence
    assert_nil report.book_title
    assert_equal @book.id, report.book_id
  end

  private

  def build_report(attrs = {})
    Report.new({ user: @user, classroom: @classroom, body: "본문입니다." }.merge(attrs))
  end
end
