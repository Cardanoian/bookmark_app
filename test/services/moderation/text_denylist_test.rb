require "test_helper"

# 금칙어 필터 공용화(reading_discussion). QUIZ 리스트는 QuizModerator 동작 보존용이라 넓고,
# FORUM 리스트는 학생 자유입력 저장 거부용이라 오탐 위험 낱말(새끼·꺼져)을 뺀 것이 핵심이다.
class Moderation::TextDenylistTest < ActiveSupport::TestCase
  test "clear profanity is flagged in both lists" do
    assert Moderation::TextDenylist.flagged?("이건 씨발 이다", list: Moderation::TextDenylist::QUIZ)
    assert Moderation::TextDenylist.flagged?("이건 씨발 이다", list: Moderation::TextDenylist::FORUM)
  end

  test "ambiguous substrings are flagged by QUIZ but NOT by FORUM (false-positive avoidance)" do
    # '곰 새끼'(동물 새끼)·'불이 꺼져'는 정상 표현. QUIZ(비파괴 게시제외)는 걸러도, FORUM(저장거부)은 통과.
    assert Moderation::TextDenylist.flagged?("곰 새끼", list: Moderation::TextDenylist::QUIZ)
    assert_not Moderation::TextDenylist.flagged?("곰 새끼", list: Moderation::TextDenylist::FORUM)
    assert_not Moderation::TextDenylist.flagged?("촛불이 꺼져서 무서웠어요", list: Moderation::TextDenylist::FORUM)
  end

  test "개새끼 (unambiguous) is still blocked by FORUM" do
    assert Moderation::TextDenylist.flagged?("개새끼", list: Moderation::TextDenylist::FORUM)
  end

  test "clean text passes both lists" do
    assert_empty Moderation::TextDenylist.hits("강아지가 새끼를 낳았어요", list: Moderation::TextDenylist::FORUM)
    assert_empty Moderation::TextDenylist.hits("오늘 책을 읽고 감동했어요", list: Moderation::TextDenylist::QUIZ)
  end

  test "hits defaults to the QUIZ list (QuizModerator behavior preserved)" do
    assert_equal Moderation::TextDenylist.hits("씨발", list: Moderation::TextDenylist::QUIZ),
                 Moderation::TextDenylist.hits("씨발")
  end
end
