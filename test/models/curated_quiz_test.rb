require "test_helper"

# 큐레이션 게임 문항(Stage 2) — payload presence + [book_id, content_axis] uniqueness.
class CuratedQuizTest < ActiveSupport::TestCase
  setup do
    @book = Book.create!(title: "큐레이션책", author: "김작가", category: :recommended)
  end

  def valid_mcq_payload
    [ { "prompt" => "주인공은?", "choices" => %w[가 나 다 라], "answer_index" => 0, "explanation" => "해설", "difficulty" => 1 } ]
  end

  test "content_axis enum 은 이 모델 전용 정수 매핑(mcq=0/hint_reveal=1)" do
    assert_equal({ "mcq" => 0, "hint_reveal" => 1 }, CuratedQuiz.defined_enums["content_axis"])
  end

  test "유효한 큐레이션은 저장된다" do
    curated = CuratedQuiz.new(book: @book, content_axis: :mcq, payload: valid_mcq_payload)
    assert curated.valid?, curated.errors.full_messages.to_sentence
  end

  test "payload 는 필수(presence)" do
    assert CuratedQuiz.new(book: @book, content_axis: :mcq, payload: nil).invalid?
    assert CuratedQuiz.new(book: @book, content_axis: :mcq, payload: []).invalid?
  end

  test "content_axis 는 book 안에서 유일(모델 검증)" do
    CuratedQuiz.create!(book: @book, content_axis: :mcq, payload: valid_mcq_payload)
    dup = CuratedQuiz.new(book: @book, content_axis: :mcq, payload: valid_mcq_payload)
    assert dup.invalid?
    assert_includes dup.errors[:content_axis], I18n.t("errors.messages.taken")
  end

  test "content_axis 유일성은 DB 유니크 인덱스로도 보증(검증 우회 시)" do
    CuratedQuiz.create!(book: @book, content_axis: :mcq, payload: valid_mcq_payload)
    dup = CuratedQuiz.new(book: @book, content_axis: :mcq, payload: valid_mcq_payload)
    assert_raises(ActiveRecord::RecordNotUnique) do
      dup.save!(validate: false)
    end
  end

  test "서로 다른 content_axis 는 같은 book 에 공존한다" do
    CuratedQuiz.create!(book: @book, content_axis: :mcq, payload: valid_mcq_payload)
    other = CuratedQuiz.new(book: @book, content_axis: :hint_reveal,
                            payload: [ { "answer" => "잎싹", "hints" => [ "동물", "두 글자" ], "explanation" => "", "difficulty" => 1 } ])
    assert other.valid?
    assert_nothing_raised { other.save! }
  end
end
