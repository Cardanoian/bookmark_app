require "test_helper"

# 무외부호출 규칙기반 뒷이야기 격려 코멘트(무중단 폴백). 항상 성공·항상 긍정·결정적을 검증한다.
class Ai::RuleBasedSequelFeedbackTest < ActiveSupport::TestCase
  test "returns a non-blank encouraging comment string" do
    comment = Ai::RuleBasedSequelFeedback.new.call(body: "주인공은 새로운 친구를 만나 모험을 이어 갔어요.")
    assert_kind_of String, comment
    assert comment.present?
  end

  test "never crashes and stays positive even for a blank body" do
    comment = Ai::RuleBasedSequelFeedback.new.call(body: "")
    assert comment.present?
    assert_includes comment, "멋져요"
  end

  test "is deterministic for identical input" do
    body = "책이 끝난 뒤의 이야기를 상상해 보았어요."
    assert_equal Ai::RuleBasedSequelFeedback.new.call(body: body),
                 Ai::RuleBasedSequelFeedback.new.call(body: body)
  end

  test "a longer story earns different praise than a short one" do
    long_praise = Ai::RuleBasedSequelFeedback.new.call(body: "가" * 320)
    short_praise = Ai::RuleBasedSequelFeedback.new.call(body: "짧은 이야기예요.")
    assert_not_equal long_praise, short_praise
  end

  test "does not assign any score or grade wording" do
    comment = Ai::RuleBasedSequelFeedback.new.call(body: "이야기를 이어 썼어요.")
    assert_no_match(/점|등급|별점|\d\s*\/\s*\d/, comment)
  end
end
