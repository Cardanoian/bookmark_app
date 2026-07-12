require "test_helper"

# Phase 1 §1.2 — 문항 채점기 4종. 정답·부분점수·힌트 서버권위 차감을 증명한다.
class Games::QuestionScorerTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "채점초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "채점교사", password: "password", role: :teacher)
    @quiz = Quiz.create!(title: "채점 퀴즈", created_by: @teacher, scope: :global)
  end

  def question(attrs)
    @quiz.quiz_questions.create!({ prompt: "문항", position: 1 }.merge(attrs))
  end

  # ── mcq_single ──────────────────────────────────────────────────────────
  test "mcq_single scores an exact index match" do
    q = question(question_type: :mcq_single, choices: %w[가 나 다], answer_index: 1)
    hit = Games::QuestionScorer.for(q).score(1)
    miss = Games::QuestionScorer.for(q).score(0)

    assert_equal 5, hit[:score]
    assert hit[:correct]
    refute hit[:partial]
    assert_equal 0, miss[:score]
    refute miss[:correct]
  end

  # ── mcq_multi ───────────────────────────────────────────────────────────
  test "mcq_multi awards a correct-set partial score" do
    q = question(question_type: :mcq_multi, choices: %w[가 나 다 라], answer: [ 0, 2 ])

    full = Games::QuestionScorer.for(q).score([ 0, 2 ])
    partial = Games::QuestionScorer.for(q).score([ 0 ])
    penalized = Games::QuestionScorer.for(q).score([ 0, 1 ]) # 정답 1 + 오답 1 → 상쇄

    assert_equal 10, full[:score]
    assert full[:correct]
    refute full[:partial]

    assert_equal 5, partial[:score]
    refute partial[:correct]
    assert partial[:partial]

    assert_equal 0, penalized[:score]
    refute penalized[:correct]
  end

  # ── matching ────────────────────────────────────────────────────────────
  test "matching awards a pair-map partial score" do
    q = question(question_type: :matching,
                 content: { "left" => %w[사과 바나나 포도], "right" => %w[빨강 노랑 보라] },
                 answer: { "0" => 0, "1" => 1, "2" => 2 })

    full = Games::QuestionScorer.for(q).score({ "0" => 0, "1" => 1, "2" => 2 })
    partial = Games::QuestionScorer.for(q).score({ "0" => 0, "1" => 2, "2" => 2 }) # 2쌍만 일치
    empty = Games::QuestionScorer.for(q).score({})

    assert_equal 15, full[:score]
    assert full[:correct]

    assert_equal 10, partial[:score]
    assert partial[:partial]
    refute partial[:correct]

    assert_equal 0, empty[:score]
    refute empty[:participation]
  end

  # ── hint_reveal (서버 권위 차감, C1) ──────────────────────────────────────
  test "hint_reveal deducts by the SERVER hint count, not a client claim" do
    q = question(question_type: :hint_reveal,
                 content: { "hints" => [ "힌트1", "힌트2", "힌트3" ] },
                 answer: "홍길동")

    no_hint = Games::QuestionScorer.for(q).score("홍길동", hints_used: 0)
    two_hints = Games::QuestionScorer.for(q).score("홍길동", hints_used: 2)
    many_hints = Games::QuestionScorer.for(q).score("홍길동", hints_used: 10)
    wrong = Games::QuestionScorer.for(q).score("임꺽정", hints_used: 0)

    assert_equal 5, no_hint[:score]
    refute no_hint[:partial]

    assert_equal 3, two_hints[:score], "서버 힌트 2개 → 2점 차감"
    assert two_hints[:partial]

    assert_equal 1, many_hints[:score], "차감해도 최소 1점 보장"

    assert_equal 0, wrong[:score]
    refute wrong[:correct]
  end

  test "hint_reveal ignores the client and uses only the server-provided count" do
    q = question(question_type: :hint_reveal,
                 content: { "hints" => [ "힌트1", "힌트2" ] },
                 answer: "정답")

    # 동일한 정답 응답이라도 서버가 넘긴 hints_used 만이 점수를 결정한다(클라이언트 위조 무력화).
    honest = Games::QuestionScorer.for(q).score("정답", hints_used: 3)
    forged_but_server_knows = Games::QuestionScorer.for(q).score("정답", hints_used: 3)

    assert_equal honest[:score], forged_but_server_knows[:score]
    assert_equal 2, honest[:score]
  end

  test "for raises on an unknown question_type" do
    q = question(question_type: :mcq_single, choices: %w[가 나], answer_index: 0)
    q.define_singleton_method(:question_type) { "unknown" }
    assert_raises(ArgumentError) { Games::QuestionScorer.for(q) }
  end
end
