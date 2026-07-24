require "test_helper"

# Phase 2b §2b.3 (R4/시나리오2) — 게시 전 안전 검증기. 보장은 구조 유효성 + 금칙어 denylist +
# (선택)LLM 자가검토뿐(미묘한 환각·편향은 못 잡음, 과대주장 금지). 실패 → 호출자는 오프라인 유지.
class Ai::QuizModeratorTest < ActiveSupport::TestCase
  # DI 스텁(다른 테스트 파일의 내부 클래스에 의존하지 않도록 로컬 정의).
  class StubClient
    def initialize(configured:, response: nil)
      @configured = configured
      @response = response
    end

    def configured? = @configured
    def generate(**) = @response
  end

  setup do
    @book = Book.create!(title: "검열책", author: "지은이", summary: "잎싹의 자유를 향한 모험 이야기.", category: :recommended)
    @service = Ai::QuizDraftService.new(client: StubClient.new(configured: false))
    @moderator = Ai::QuizModerator.new(client: StubClient.new(configured: false))
  end

  # 정상 오프라인 세트는 3개 축 모두 통과(결정적·안전).
  test "well-formed offline sets pass for every content axis" do
    ReadingDomain::CONTENT_COUNTS.each_key do |axis|
      set = @service.offline_set(@book, :g56, axis)
      result = @moderator.review(set, content_axis: axis)
      assert result.pass?, "#{axis} 정상 세트가 거부됨: #{result.reasons.inspect}"
    end
  end

  test "denylisted content is rejected" do
    set = @service.offline_set(@book, :g56, :mcq)
    set.first[:prompt] = "이 문장에는 씨발 이라는 금칙어가 있다"
    result = @moderator.review(set, content_axis: :mcq)
    assert result.fail?
    assert(result.reasons.any? { |r| r.include?("금칙어") })
  end

  test "wrong mcq count is rejected" do
    set = @service.offline_set(@book, :g56, :mcq).first(3) # 5→3
    result = @moderator.review(set, content_axis: :mcq)
    assert result.fail?
    assert(result.reasons.any? { |r| r.include?("문항 수") })
  end

  test "mcq with an out-of-range answer index is rejected" do
    set = @service.offline_set(@book, :g56, :mcq)
    set.first[:answer_index] = 9
    result = @moderator.review(set, content_axis: :mcq)
    assert result.fail?
    assert(result.reasons.any? { |r| r.include?("정답 인덱스") })
  end

  test "mcq with duplicate choices (not mutually distinct) is rejected" do
    set = @service.offline_set(@book, :g56, :mcq)
    set.first[:choices] = %w[같다 같다 다르다 또다르다]
    result = @moderator.review(set, content_axis: :mcq)
    assert result.fail?
    assert(result.reasons.any? { |r| r.include?("중복") })
  end

  test "hint_reveal without a target is rejected" do
    set = @service.offline_set(@book, :g34, :hint_reveal)
    set.first[:answer] = ""
    result = @moderator.review(set, content_axis: :hint_reveal)
    assert result.fail?
    assert(result.reasons.any? { |r| r.include?("타깃") })
  end

  # LLM 자가검토는 키가 있을 때만. 임계 이상 suspicion → 거부.
  test "optional LLM self-check rejects when suspicion is over threshold" do
    flagging = StubClient.new(configured: true, response: { "suspicion" => 0.9 })
    moderator = Ai::QuizModerator.new(client: flagging)
    set = @service.offline_set(@book, :g56, :mcq)
    result = moderator.review(set, content_axis: :mcq)
    assert result.fail?
    assert(result.reasons.any? { |r| r.include?("LLM") })
  end

  # 무키 → LLM 자가검토 생략(구조·금칙어만으로 판정, 무중단).
  test "without a key the LLM self-check is skipped and structure-valid sets still pass" do
    set = @service.offline_set(@book, :g56, :mcq)
    result = @moderator.review(set, content_axis: :mcq)
    assert result.pass?
  end
end
