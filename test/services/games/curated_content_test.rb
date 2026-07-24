require "test_helper"

# Games::CuratedContent(Stage 2) — set_for 균일 문항 해시 변환(mcq_single/hint_reveal 키·형태) + available?.
class Games::CuratedContentTest < ActiveSupport::TestCase
  setup do
    @book = Book.create!(title: "큐레이션책", author: "김작가", category: :recommended)
  end

  def seed_mcq!
    CuratedQuiz.create!(book: @book, content_axis: :mcq, payload: [
      { "prompt" => "주인공은 누구인가요?", "choices" => %w[잎싹 나그네 청둥오리 족제비],
        "answer_index" => 0, "explanation" => "잎싹이 주인공이에요.", "difficulty" => 1 }
    ])
  end

  def seed_hint_reveal!
    CuratedQuiz.create!(book: @book, content_axis: :hint_reveal, payload: [
      { "answer" => "잎싹", "hints" => [ "암탉이에요", "두 글자예요" ], "explanation" => "정답은 잎싹.", "difficulty" => 2 }
    ])
  end

  # ── available? ─────────────────────────────────────────────────────────
  test "available? is true only for a book+axis that has curated content" do
    seed_mcq!
    assert Games::CuratedContent.available?(@book, :mcq)
    assert Games::CuratedContent.available?(@book, "mcq"), "문자열 축도 허용"
    assert_not Games::CuratedContent.available?(@book, :hint_reveal), "다른 축은 없음"
    assert_not Games::CuratedContent.available?(nil, :mcq), "book nil 이면 false"
  end

  test "available_for_any_axis? is true when any axis has curated content" do
    assert_not Games::CuratedContent.available_for_any_axis?(@book)
    seed_hint_reveal!
    assert Games::CuratedContent.available_for_any_axis?(@book)
  end

  # ── set_for: 균일 문항 해시 변환 ─────────────────────────────────────────
  test "set_for returns nil when there is no curated row" do
    assert_nil Games::CuratedContent.set_for(@book, :mcq)
    assert_nil Games::CuratedContent.set_for(nil, :mcq)
  end

  test "set_for converts an mcq payload into build_questions-consumable hashes" do
    seed_mcq!
    set = Games::CuratedContent.set_for(@book, :mcq)

    assert_equal 1, set.size
    item = set.first
    assert_equal "mcq_single", item[:question_type]
    assert_equal "주인공은 누구인가요?", item[:prompt]
    assert_equal %w[잎싹 나그네 청둥오리 족제비], item[:choices]
    assert_equal 0, item[:answer_index]
    assert_equal({ prompt: "주인공은 누구인가요?", choices: %w[잎싹 나그네 청둥오리 족제비] }, item[:content])
    assert_equal 0, item[:answer], "mcq answer 는 answer_index 값과 동일"
    assert_equal "잎싹이 주인공이에요.", item[:explanation]
    assert_equal 1, item[:difficulty]
  end

  test "set_for converts a hint_reveal payload into build_questions-consumable hashes" do
    seed_hint_reveal!
    set = Games::CuratedContent.set_for(@book, :hint_reveal)

    item = set.first
    assert_equal "hint_reveal", item[:question_type]
    assert_equal "힌트를 보고 정답을 맞혀 보세요.", item[:prompt]
    assert_equal({ hints: [ "암탉이에요", "두 글자예요" ] }, item[:content])
    assert_equal "잎싹", item[:answer]
    assert_equal "정답은 잎싹.", item[:explanation]
    assert_equal 2, item[:difficulty]
  end

  # 변환 결과가 실제로 ContentProvider.build_questions 로 유효 문항이 되는지(계약 확인).
  test "set_for output builds valid quiz_questions via ContentProvider.build_questions" do
    seed_mcq!
    quiz = Quiz.new(title: "t", created_by: Games::ContentProvider.system_user, book: @book,
                    scope: :global, published: true, origin: :system, content_axis: :mcq,
                    band: :g56, content_version: 1, generation_status: :ready)
    Games::ContentProvider.build_questions(quiz, Games::CuratedContent.set_for(@book, :mcq), source: :curated)
    quiz.save!

    assert_equal 1, quiz.quiz_questions.count
    assert_equal [ "curated" ], quiz.quiz_questions.pluck(:source).uniq
    assert quiz.quiz_questions.first.valid?
  end
end
