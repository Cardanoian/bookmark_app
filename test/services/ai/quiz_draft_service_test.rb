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

  # ── Phase 2a: content_axis 세트(오프라인 C2 + AI normalize) ────────────────────
  BANNED_DISTRACTORS = %w[김유신 장영실 구름빵].freeze

  # generate 를 부르면 예외를 던져 "네트워크 0"(오프라인 무호출)을 강제하는 스텁.
  class NoNetworkClient
    attr_reader :calls

    def initialize(configured:)
      @configured = configured
      @calls = 0
    end

    def configured? = @configured

    def generate(**)
      @calls += 1
      raise "offline path must not call the client"
    end
  end

  test "offline_set mcq derives book-based items with title and summary tokens, no hardcoded distractors" do
    service = Ai::QuizDraftService.new(client: StubClient.new(configured: false))
    set = service.offline_set(@book, :g56, :mcq)

    assert_equal ReadingDomain::CONTENT_COUNTS[:mcq], set.size
    joined = set.map { |q| [ q[:prompt], q[:choices].join(" "), q[:explanation] ].join(" ") }.join(" ")
    assert_includes joined, @book.title, "책 제목 토큰 부재"
    assert_includes joined, "잎싹의", "줄거리 토큰 부재"
    BANNED_DISTRACTORS.each { |banned| refute_includes joined, banned, "하드코딩 오답 #{banned} 잔존" }

    set.each do |question|
      assert_equal "mcq_single", question[:question_type]
      assert_equal 4, question[:choices].size
      assert_includes 0...4, question[:answer_index]
      assert question[:choices][question[:answer_index]].present?
      assert question[:explanation].present?, "해설 부재"
      assert_includes 1..3, question[:difficulty]
    end
  end

  test "offline_set embeds the book author as a choice (back-compat)" do
    set = Ai::QuizDraftService.new(client: StubClient.new(configured: false)).offline_set(@book, :g56, :mcq)
    assert(set.any? { |question| question[:choices].include?(@book.author) })
  end

  # §2b 검증 후속 [LOW/edge] — summary_distractors 가 요약에 실린 낱말이 많아 오답<3 를 반환해도
  # (오프라인은 Moderator 미경유라 학생에게 바로 노출) 보기는 항상 정확히 4개·서로 겹치지 않아야 한다.
  test "offline mcq keeps exactly 4 distinct choices even when the summary exhausts the distractor pool" do
    # SUMMARY_DISTRACTOR_POOL(10개 낱말)을 모두 포함시켜 summary_distractors 가 빈 배열을
    # 반환하는 최악의 경우(오답 0개)를 강제한다.
    summary = "사과 바람 연필 시계 우산 거울 모자 지도 풍선 그림자 모두 나오는 이야기"
    book = Book.create!(title: "패딩책", author: "지은이", summary: summary, category: :recommended)

    set = Ai::QuizDraftService.new(client: StubClient.new(configured: false)).offline_set(book, :g56, :mcq)

    set.each do |question|
      assert_equal 4, question[:choices].size, "오답 풀이 부족해도 보기는 항상 4개(정답1+오답3)"
      assert_equal question[:choices].size, question[:choices].uniq.size, "보기가 서로 겹치면 안 된다"
      assert question[:choices][question[:answer_index]].present?
    end
  end

  test "offline_set mcq degrades to general reading when summary is blank" do
    book = Book.create!(title: "제목만 있는 책", author: "글쓴이", category: :recommended)
    set = Ai::QuizDraftService.new(client: StubClient.new(configured: false)).offline_set(book, :g56, :mcq)

    assert_equal ReadingDomain::CONTENT_COUNTS[:mcq], set.size
    joined = set.map { |question| question.values.join(" ") }.join(" ")
    BANNED_DISTRACTORS.each { |banned| refute_includes joined, banned }
    set.each do |question|
      assert_equal 4, question[:choices].size
      assert question[:explanation].present?
    end
  end

  test "offline_set matching uses only guaranteed-correct pairs with enforced count" do
    set = Ai::QuizDraftService.new(client: StubClient.new(configured: false)).offline_set(@book, :g56, :matching)

    assert_equal 1, set.size
    question = set.first
    assert_equal "matching", question[:question_type]
    assert_equal ReadingDomain::CONTENT_COUNTS[:matching], question[:content][:lefts].size
    assert_equal ReadingDomain::CONTENT_COUNTS[:matching], question[:content][:rights].size
    # answer 맵의 각 우 인덱스가 rights 배열 안에서 정답 뜻을 실제로 가리키는지(보장된 정답).
    question[:answer].each do |left_index, right_index|
      pair_meaning = question[:content][:rights][right_index.to_i]
      assert pair_meaning.present?, "left #{left_index} 정답 우 인덱스 무효"
    end
  end

  test "offline_set hint_reveal has target and ordered hints" do
    set = Ai::QuizDraftService.new(client: StubClient.new(configured: false)).offline_set(@book, :g34, :hint_reveal)

    assert_equal ReadingDomain::CONTENT_COUNTS[:hint_reveal], set.size
    set.each do |question|
      assert_equal "hint_reveal", question[:question_type]
      assert question[:answer].present?
      assert_operator question[:content][:hints].size, :>=, 2
    end
  end

  test "offline_set is band-differentiated (g12 vs g56 differ) for every axis" do
    service = Ai::QuizDraftService.new(client: StubClient.new(configured: false))
    ReadingDomain::CONTENT_COUNTS.each_key do |axis|
      refute_equal service.offline_set(@book, :g12, axis), service.offline_set(@book, :g56, axis), "#{axis} band 미분화"
    end
  end

  test "offline and unconfigured paths never call the client (network 0)" do
    client = NoNetworkClient.new(configured: false)
    service = Ai::QuizDraftService.new(client: client)
    ReadingDomain::CONTENT_COUNTS.each_key { |axis| service.content_set(@book, :g56, axis) }
    service.offline_set(@book, :g56, :mcq)
    assert_equal 0, client.calls
  end

  test "content_set mcq normalizes a well-formed AI response and enforces count" do
    questions = (1..6).map do |i|
      { "prompt" => "질문#{i}", "choices" => [ "가", "나", "다", "라" ], "answer_index" => (i % 4), "explanation" => "해설#{i}", "difficulty" => 2 }
    end
    client = StubClient.new(configured: true, response: { "questions" => questions })
    set = Ai::QuizDraftService.new(client: client).content_set(@book, :g56, :mcq)

    assert_equal ReadingDomain::CONTENT_COUNTS[:mcq], set.size, "count 6→5 강제 실패"
    assert_equal "질문1", set.first[:prompt]
    set.each { |question| assert_equal "mcq_single", question[:question_type] }
  end

  test "content_set mcq rejects multiple-correct answers and falls back to book-based offline" do
    bad = Array.new(5) { { "prompt" => "문항", "choices" => [ "가", "나", "다", "라" ], "answer_index" => [ 0, 1 ], "explanation" => "x" } }
    client = StubClient.new(configured: true, response: { "questions" => bad })
    set = Ai::QuizDraftService.new(client: client).content_set(@book, :g56, :mcq)

    assert_equal ReadingDomain::CONTENT_COUNTS[:mcq], set.size
    assert(set.all? { |question| question[:answer_index].is_a?(Integer) })
    assert_includes set.map { |question| question[:prompt] }.join(" "), @book.title, "폴백이 책 기반이 아님"
  end

  test "content_set mcq rejects blank prompts, falling back to offline" do
    bad = Array.new(5) { { "prompt" => "", "choices" => [ "가", "나", "다", "라" ], "answer_index" => 0 } }
    client = StubClient.new(configured: true, response: { "questions" => bad })
    set = Ai::QuizDraftService.new(client: client).content_set(@book, :g56, :mcq)
    assert_equal ReadingDomain::CONTENT_COUNTS[:mcq], set.size
  end

  test "content_set matching rejects incomplete pairs, falling back to offline 5 pairs" do
    pairs = [ { "word" => "제목", "meaning" => "책의 이름" }, { "word" => "지은이" } ]
    client = StubClient.new(configured: true, response: { "pairs" => pairs })
    set = Ai::QuizDraftService.new(client: client).content_set(@book, :g56, :matching)

    assert_equal 1, set.size
    assert_equal ReadingDomain::CONTENT_COUNTS[:matching], set.first[:content][:lefts].size
  end

  test "content_set matching normalizes a complete AI response into a paired question" do
    pairs = %w[하나 둘 셋 넷 다섯].each_with_index.map { |word, i| { "word" => word, "meaning" => "뜻#{i}" } }
    client = StubClient.new(configured: true, response: { "pairs" => pairs })
    set = Ai::QuizDraftService.new(client: client).content_set(@book, :g56, :matching)

    assert_equal 1, set.size
    question = set.first
    assert_equal "matching", question[:question_type]
    assert_equal 5, question[:content][:lefts].size
    assert question[:answer].is_a?(Hash)
  end

  test "content_set hint_reveal rejects targets without enough hints, falling back to offline" do
    targets = Array.new(3) { { "answer" => "정답", "hints" => [ "하나뿐인 힌트" ] } }
    client = StubClient.new(configured: true, response: { "targets" => targets })
    set = Ai::QuizDraftService.new(client: client).content_set(@book, :g56, :hint_reveal)

    assert_equal ReadingDomain::CONTENT_COUNTS[:hint_reveal], set.size
    set.each { |question| assert_operator question[:content][:hints].size, :>=, 2 }
  end
end
