module Ai
  # 도서 기반 독서 퀴즈 초안 생성(P5.6, RAILS_PLAN §9.5). 키가 있으면 Gemini(QUIZGEN)
  # 경로, 없거나 실패하면 책 메타데이터로 만든 오프라인 템플릿 문항으로 폴백한다(무중단).
  # 반환은 항상 [{ prompt:, choices:[], answer_index: }, ...] 초안 배열(교사 검수 후 published).
  class QuizDraftService
    # LLM 응답이 스키마를 벗어났을 때 → 폴백 신호.
    class InvalidResponse < StandardError; end

    DEFAULT_COUNT = 4

    def initialize(client: GeminiClient.new)
      @client = client
    end

    # book: Book. count: 생성 문항 수. 반환: 문항 초안 배열(symbol 키).
    def call(book, count: DEFAULT_COUNT)
      return offline_questions(book, count) unless @client.configured?

      response = @client.generate(
        contents: build_contents(book, count),
        system_instruction: ReadingDomain::QUIZGEN_PROMPT,
        response_json: true
      )
      normalize(response)
    rescue GeminiClient::NotConfigured, GeminiClient::ApiError, InvalidResponse
      offline_questions(book, count)
    end

    private

    def build_contents(book, count)
      prompt = +"책 제목: #{book.title}\n"
      prompt << "지은이: #{book.author}\n" if book.author.present?
      prompt << "줄거리: #{book.summary}\n" if book.summary.present?
      prompt << "\n위 책으로 #{count}개의 4지선다 독서 퀴즈 문항을 만들어 주세요."
      [ { role: "user", parts: [ { text: prompt } ] } ]
    end

    def normalize(response)
      raise InvalidResponse, "response was not a Hash" unless response.is_a?(Hash)

      questions = Array(response["questions"]).map { |raw| normalize_question(raw) }
      raise InvalidResponse, "no questions" if questions.empty?

      questions
    end

    def normalize_question(raw)
      raise InvalidResponse, "question was not a Hash" unless raw.is_a?(Hash)

      data = raw.symbolize_keys
      choices = Array(data[:choices]).map(&:to_s)
      answer_index = data[:answer_index].to_i
      prompt = data[:prompt].to_s
      raise InvalidResponse, "question needs >= 2 choices" if choices.size < 2
      raise InvalidResponse, "answer_index out of range" unless answer_index.between?(0, choices.size - 1)
      raise InvalidResponse, "prompt blank" if prompt.blank?

      { prompt: prompt, choices: choices, answer_index: answer_index }
    end

    # 오프라인 폴백: 책 제목·지은이·줄거리로 만든 결정적(비무작위) 템플릿 문항.
    # 정답 위치는 문항 순서에 따라 회전(i % 4)시켜 항상 같은 자리에 오지 않게 한다.
    def offline_questions(book, count)
      title = book.title.to_s
      author = book.author.presence || "지은이 미상"
      templates(title, author).first([ count, 1 ].max).each_with_index.map do |template, index|
        place_answer(template, index)
      end
    end

    def templates(title, author)
      [
        { prompt: "이 책 『#{title}』을(를) 쓴 사람은 누구인가요?",
          correct: author, distractors: [ "김유신", "장영실", "신사임당" ] },
        { prompt: "다음 중 우리가 함께 읽은 책의 제목은 무엇인가요?",
          correct: title, distractors: [ "구름빵", "무지개 물고기", "아낌없이 주는 나무" ] },
        { prompt: "『#{title}』을(를) 읽고 나서 하면 좋은 독후 활동은 무엇인가요?",
          correct: "책 속 인물에게 마음을 담아 편지 쓰기",
          distractors: [ "교과서를 그대로 베껴 쓰기", "표지만 색칠하고 덮어 두기", "제목만 소리 내어 외우기" ] },
        { prompt: "책을 깊이 있게 읽는 좋은 방법은 무엇일까요?",
          correct: "인상 깊은 장면과 그 까닭을 함께 떠올리기",
          distractors: [ "글자 수만 빠르게 세기", "그림만 넘겨 보기", "마지막 쪽만 읽기" ] },
        { prompt: "독후감을 쓸 때 A등급으로 나아가는 방법은 무엇인가요?",
          correct: "책 내용을 내 삶·경험과 연결해 생각 쓰기",
          distractors: [ "줄거리만 길게 옮겨 적기", "맞춤법 신경 쓰지 않기", "느낌 없이 제목만 적기" ] }
      ]
    end

    def place_answer(template, index)
      correct = template[:correct]
      options = ([ correct ] + template[:distractors]).first(4)
      answer_index = index % options.size
      choices = options.reject { |option| option == correct }
      choices.insert(answer_index, correct)
      { prompt: template[:prompt], choices: choices, answer_index: answer_index }
    end
  end
end
