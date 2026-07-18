require "test_helper"

# WS-D2 — 오프라인 장르 추론(무API). 가중 n-gram 코사인 kNN + 규칙 폴백(STRONG_GENRE_RULES).
# Book 레코드/해시 두 입력을 모두 받고, 외부 호출 없이 순수 계산으로만 장르를 뽑는다.
class Books::GenreInferenceTest < ActiveSupport::TestCase
  test "유사한 이웃이 한 장르로 몰리면 그 장르를 뽑는다(kNN)" do
    neighbors = [
      Book.new(title: "해리 포터와 마법사의 돌", author: "조앤 롤링", publisher: "문학수첩", genre: "문학"),
      Book.new(title: "해리 포터와 비밀의 방", author: "조앤 롤링", publisher: "문학수첩", genre: "문학"),
      Book.new(title: "수학의 정석 기초편", author: "홍성대", publisher: "성지출판", genre: "자연과학")
    ]

    result = Books::GenreInference.new(neighbors).infer(
      Book.new(title: "해리 포터와 불의 잔", author: "조앤 롤링", publisher: "문학수첩")
    )

    assert_equal "문학", result.genre
    assert_operator result.confidence, :>, 0.0
  end

  test "kNN 신뢰도가 낮으면(장르 갈림) 강한 규칙이 우선한다(맞춤법→언어)" do
    neighbors = [
      Book.new(title: "빛나는 보석 이야기", author: "가", publisher: "출판가", genre: "자연과학"),
      Book.new(title: "빛나는 보석 이야기", author: "나", publisher: "출판나", genre: "예술·체육")
    ]

    result = Books::GenreInference.new(neighbors).infer(
      Book.new(title: "빛나는 보석 맞춤법 왕", author: "다")
    )

    assert_equal "언어", result.genre, "이웃 장르가 갈려 신뢰도 0.5 → 규칙(맞춤법→언어) 오버라이드"
    assert_operator result.confidence, :>=, Books::GenreInference::RULE_OVERRIDE_CONFIDENCE
  end

  test "공유 특징이 없으면 최빈 장르로 폴백한다(신뢰도 0)" do
    neighbors = [
      Book.new(title: "완전히 다른 제목 하나", genre: "자연과학"),
      Book.new(title: "전혀 겹치지 않는 둘", genre: "자연과학"),
      Book.new(title: "공통점 없는 셋", genre: "문학")
    ]

    result = Books::GenreInference.new(neighbors).infer(Book.new(title: "qwer asdf zxcv"))

    assert_equal "자연과학", result.genre
    assert_equal 0.0, result.confidence
  end

  test "미분류·공란 이웃은 추론에서 제외하고, 분류된 이웃이 하나도 없으면 규칙만으로 추론한다(크래시 없음)" do
    result = nil
    assert_nothing_raised do
      result = Books::GenreInference.new([
        Book.new(title: "책1", genre: "미분류"),
        Book.new(title: "책2", genre: ""),
        Book.new(title: "책3", genre: nil)
      ]).infer(Book.new(title: "받아쓰기 급수 왕"))
    end

    assert_equal "언어", result.genre, "분류된 이웃 0 → 규칙(받아쓰기→언어)으로만 추론"
  end

  test "심볼 키 해시 입력도 그대로 받는다(script 판본 하위호환)" do
    result = Books::GenreInference.new([
      { title: "해리 포터와 마법사의 돌", author: "조앤 롤링", publisher: "문학수첩", genre: "문학" },
      { title: "해리 포터와 비밀의 방", author: "조앤 롤링", publisher: "문학수첩", genre: "문학" }
    ]).infer(title: "해리 포터와 아즈카반의 죄수", author: "조앤 롤링", publisher: "문학수첩")

    assert_equal "문학", result.genre
  end
end
