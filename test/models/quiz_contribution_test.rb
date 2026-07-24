require "test_helper"

# 학생 출제 기여(전국 공유 문제은행 UGC, Phase 3 §4). 축별 페이로드 검증·status enum·금칙어.
class QuizContributionTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "기여초")
    @room = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @room, name: "기여학생", password: "password")
    @book = Book.create!(title: "기여책", author: "김작가", category: :recommended)
  end

  def build(axis:, payload:, band: :g56)
    QuizContribution.new(user: @student, book: @book, classroom: @room,
                         content_axis: axis, band: band, payload: payload)
  end

  test "status defaults to pending and enum maps to 0/1/2" do
    contribution = build(axis: :mcq, payload: valid_mcq)
    assert contribution.pending?
    assert_equal({ "pending" => 0, "approved" => 1, "rejected" => 2 }, QuizContribution.statuses)
  end

  test "a valid mcq payload passes" do
    assert build(axis: :mcq, payload: valid_mcq).valid?
  end

  test "mcq requires exactly four choices" do
    contribution = build(axis: :mcq, payload: valid_mcq.merge("choices" => %w[가 나 다]))
    assert_not contribution.valid?
    assert contribution.errors[:payload].any?
  end

  test "mcq requires an answer_index within range" do
    assert_not build(axis: :mcq, payload: valid_mcq.merge("answer_index" => 9)).valid?
    assert_not build(axis: :mcq, payload: valid_mcq.merge("answer_index" => nil)).valid?
  end

  test "mcq requires a non-blank prompt" do
    assert_not build(axis: :mcq, payload: valid_mcq.merge("prompt" => "  ")).valid?
  end

  test "a valid hint_reveal payload passes" do
    assert build(axis: :hint_reveal, payload: valid_hint).valid?
  end

  test "hint_reveal requires an answer and at least two hints" do
    assert_not build(axis: :hint_reveal, payload: valid_hint.merge("answer" => "")).valid?
    assert_not build(axis: :hint_reveal, payload: valid_hint.merge("hints" => [ "하나" ])).valid?
  end

  test "denylisted text is rejected across payload fields" do
    assert_not build(axis: :hint_reveal, payload: valid_hint.merge("answer" => "씨발")).valid?
    assert_not build(axis: :mcq, payload: valid_mcq.merge("choices" => [ "지랄", "나", "다", "라" ])).valid?
  end

  private

  def valid_mcq
    { "prompt" => "주인공은 누구인가요?", "choices" => %w[가 나 다 라], "answer_index" => 1, "explanation" => "해설이에요." }
  end

  def valid_hint
    { "answer" => "잎싹", "hints" => [ "동물이에요", "두 글자예요" ], "explanation" => "" }
  end
end
