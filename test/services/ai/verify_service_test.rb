require "test_helper"

class Ai::VerifyServiceTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "검증학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "검증학생", password: "password")
  end

  class StubClient
    def initialize(configured:, response: nil, error: nil)
      @configured = configured
      @response = response
      @error = error
    end

    def configured? = @configured

    def generate(**)
      raise @error if @error

      @response
    end
  end

  test "returns a neutral result when unconfigured" do
    result = Ai::VerifyService.new(client: StubClient.new(configured: false)).call(create_report(body: "본문"))
    assert_nil result[:suspicion]
    assert_equal [], result[:reasons]
  end

  test "returns the model suspicion and reasons when configured" do
    client = StubClient.new(configured: true, response: { "suspicion" => 0.7, "reasons" => [ "표절 의심" ] })
    result = Ai::VerifyService.new(client: client).call(create_report(body: "본문"))

    assert_equal 0.7, result[:suspicion]
    assert_equal [ "표절 의심" ], result[:reasons]
  end

  test "returns a neutral result on ApiError" do
    client = StubClient.new(configured: true, error: Ai::GeminiClient::ApiError.new("boom"))
    result = Ai::VerifyService.new(client: client).call(create_report(body: "본문"))

    assert_nil result[:suspicion]
    assert_equal [], result[:reasons]
  end

  test "max_similarity is zero when the classroom has no other reports" do
    report = create_report(body: "혼자 있는 글입니다.")
    assert_equal 0.0, Ai::VerifyService.max_similarity(report)
  end

  test "max_similarity is zero when there is no token overlap" do
    report = create_report(body: "사과 바나나 포도")
    create_report(body: "자동차 기차 비행기")
    assert_equal 0.0, Ai::VerifyService.max_similarity(report)
  end

  test "max_similarity detects overlap within the classroom and stays in 0..1" do
    report = create_report(body: "강아지 고양이 토끼 거북이")
    create_report(body: "강아지 고양이 토끼 다람쥐")

    similarity = Ai::VerifyService.max_similarity(report)
    assert_operator similarity, :>, 0.0
    assert_operator similarity, :<=, 1.0
  end

  private

  def create_report(body:)
    Report.create!(user: @user, classroom: @classroom, book_title: "책", body: body)
  end
end
