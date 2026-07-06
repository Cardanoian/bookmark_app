require "test_helper"

class Ai::QuizDraftServiceTest < ActiveSupport::TestCase
  setup do
    @book = Book.create!(title: "마당을 나온 암탉", author: "황선미", summary: "잎싹의 성장 이야기.", category: :recommended)
  end

  # ReviewService 테스트와 동일한 DI 스텁 패턴(Minitest 6 은 minitest/mock 없음).
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

  test "offline fallback generates template questions without network" do
    questions = Ai::QuizDraftService.new(client: StubClient.new(configured: false)).call(@book, count: 4)

    assert_equal 4, questions.size
    questions.each do |question|
      assert question[:prompt].present?
      assert_operator question[:choices].size, :>=, 2
      assert_includes 0...question[:choices].size, question[:answer_index]
      assert question[:choices][question[:answer_index]].present?
    end
  end

  test "offline fallback embeds the book title and author" do
    questions = Ai::QuizDraftService.new(client: StubClient.new(configured: false)).call(@book, count: 2)
    joined = questions.map { |q| q[:prompt] }.join(" ")
    assert_includes joined, @book.title
    assert questions.any? { |q| q[:choices].include?(@book.author) }
  end

  test "uses the LLM response when the client is configured" do
    response = {
      "questions" => [
        { "prompt" => "잎싹의 꿈은?", "choices" => [ "알 품기", "하늘 날기", "잠자기", "숨기" ], "answer_index" => 0 }
      ]
    }
    questions = Ai::QuizDraftService.new(client: StubClient.new(configured: true, response: response)).call(@book)

    assert_equal 1, questions.size
    assert_equal "잎싹의 꿈은?", questions.first[:prompt]
    assert_equal 0, questions.first[:answer_index]
  end

  test "falls back to offline questions on ApiError" do
    client = StubClient.new(configured: true, error: Ai::GeminiClient::ApiError.new("boom"))
    questions = Ai::QuizDraftService.new(client: client).call(@book, count: 3)
    assert_equal 3, questions.size
  end

  test "falls back to offline questions when the schema is invalid" do
    client = StubClient.new(configured: true, response: { "questions" => [ { "prompt" => "", "choices" => [] } ] })
    questions = Ai::QuizDraftService.new(client: client).call(@book, count: 3)
    assert_equal 3, questions.size
    assert(questions.all? { |q| q[:choices].size >= 2 })
  end
end
