require "test_helper"

class StickerPolicyTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "스티커정책초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "스티커교사", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "스티커학생", password: "password")

    @visible_report = report_with_board_post(hidden: false)
    @hidden_report = report_with_board_post(hidden: true)
    @unshared_report = Report.create!(user: @student, classroom: @classroom, book_title: "미공유", body: "본문")
  end

  test "a student can sticker a report whose board post is visible" do
    assert StickerPolicy.new(@student, sticker_on(@visible_report)).create?
  end

  test "a student cannot sticker a report whose board post is hidden" do
    assert_not StickerPolicy.new(@student, sticker_on(@hidden_report)).create?
  end

  test "a student cannot sticker a report that has no board post" do
    assert_not StickerPolicy.new(@student, sticker_on(@unshared_report)).create?
  end

  test "a non-student cannot sticker even a visible report" do
    assert_not StickerPolicy.new(@teacher, sticker_on(@visible_report)).create?
  end

  test "an anonymous user cannot sticker" do
    assert_not StickerPolicy.new(nil, sticker_on(@visible_report)).create?
  end

  private

  def report_with_board_post(hidden:)
    report = Report.create!(user: @student, classroom: @classroom, book_title: "스티커책", body: "본문")
    BoardPost.create!(report: report, hidden: hidden)
    report.reload
  end

  def sticker_on(report)
    report.stickers.build(by_user: @student, emoji: "👍", position: 0)
  end
end
