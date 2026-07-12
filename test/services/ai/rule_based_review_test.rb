require "test_helper"

class Ai::RuleBasedReviewTest < ActiveSupport::TestCase
  test "returns the canonical review shape" do
    result = Ai::RuleBasedReview.new.call(
      body: "나는 이 책을 읽고 많은 생각을 했다. 우리의 삶과 연결해 보며 감동을 느꼈다.",
      book_title: "마당을 나온 암탉"
    )

    assert_includes %w[A B C], result[:level]
    assert_equal ReadingDomain::RUBRIC_AXES.sort, result[:rubric].keys.sort
    result[:rubric].each_value { |score| assert_includes 0..5, score }
    assert_kind_of Array, result[:praise]
    assert_kind_of Array, result[:fix]
    assert_kind_of Array, result[:grow]
    result[:grow].each do |entry|
      assert entry.key?(:text)
      assert entry.key?(:standard_code)
    end
    assert_includes ReadingDomain::LEVEL_POINTS.values, result[:pts]
  end

  test "is deterministic for identical input" do
    body = "재미있는 책이었다. 나는 많은 것을 느꼈다."
    assert_equal Ai::RuleBasedReview.new.call(body: body), Ai::RuleBasedReview.new.call(body: body)
  end

  test "always succeeds and grades a blank body as C" do
    result = Ai::RuleBasedReview.new.call(body: "")
    assert_equal "C", result[:level]
    assert_equal 10, result[:pts]
  end

  test "richer writing scores higher content than an empty body" do
    rich = Ai::RuleBasedReview.new.call(body: "나는 이 책을 읽으며 인물의 마음에 깊이 감동을 느꼈다. " * 20)
    empty = Ai::RuleBasedReview.new.call(body: "")

    assert_operator rich[:rubric][:content], :>, empty[:rubric][:content]
  end

  test "grow entries carry a 2022 achievement standard code" do
    codes = ReadingDomain::ACHIEVEMENT_STANDARDS.values
    result = Ai::RuleBasedReview.new.call(body: "짧은 글.")

    result[:grow].each { |entry| assert_includes codes, entry[:standard_code] }
  end

  test "grow codes follow the requested 학년군 band" do
    { g12: "2국", g34: "4국", g56: "6국" }.each do |band, prefix|
      result = Ai::RuleBasedReview.new.call(body: "짧은 글.", band: band)
      result[:grow].each { |entry| assert_match(/\A\[#{prefix}\d{2}-\d{2}\]\z/, entry[:standard_code]) }
    end
  end

  test "defaults to the 5~6학년군 codes when no band is given" do
    result = Ai::RuleBasedReview.new.call(body: "짧은 글.")
    codes = ReadingDomain.achievement_standards(:g56).values
    result[:grow].each { |entry| assert_includes codes, entry[:standard_code] }
  end
end
