module Ai
  # 도서 기반 독서 게임 콘텐츠 생성(P5.6 → Phase 2a 확장). 키가 있으면 Gemini 경로,
  # 없거나 실패하면 book.summary/title 파생 **결정적** 오프라인 세트로 폴백한다(무중단).
  #
  # 두 진입점:
  #   ① call(book, count:, band:)            — 하위호환 mcq 초안(교사 퀴즈 CRUD). count 만큼 mcq 배열.
  #   ② content_set(book, band, content_axis) — Phase 2a 콘텐츠축 세트(AI→오프라인 폴백, Phase 2b Job 진입점).
  #
  # 반환 문항 해시는 두 경로에서 동일한 형태:
  #   { question_type:, prompt:, content:, answer:, explanation:, difficulty:, ... }
  #   (mcq 는 하위호환용 choices/answer_index 도 함께 포함)
  #
  # 오프라인 세트는 무키·즉시·결정적·무중단 계약을 지킨다. 첫 판도 "이 책" 문제이지만
  # 품질은 AI 보다 낮다(정직화).
  # 게임 재구성 Phase 1: matching(vocab) 생성 경로 제거. mcq·hint_reveal 만 생성한다
  # (Quiz#content_axis matching 값·QuestionScorer matching 은 과거 기록·보존차 유지하되 여기선 생성 안 함).
  class QuizDraftService
    # LLM 응답이 스키마를 벗어났을 때 → 폴백 신호.
    class InvalidResponse < StandardError; end

    DEFAULT_COUNT = 4

    # 학년군별 오프라인 난이도(1~3). 세트가 band 별로 달라지는 축의 하나.
    BAND_DIFFICULTY = { g12: 1, g34: 2, g56: 3 }.freeze

    # 줄거리 파생 mcq 의 오답 풀. 요약에 없는 낱말만 골라 정답(요약 토큰)이 유일한 정답이 되게 한다.
    # 하드코딩 인물/작품명(김유신·장영실·구름빵)을 쓰지 않는 결정적 일반 명사 풀.
    SUMMARY_DISTRACTOR_POOL = %w[사과 바람 연필 시계 우산 거울 모자 지도 풍선 그림자].freeze

    # place_answer 의 최후 안전망 — 오답이 3개 미만일 때만(예: summary_distractors 가 요약에 실린
    # 낱말이 많아 <3개 반환) 부족분을 채우는 일반 오답. 오프라인 경로는 Moderator 게시 전 검증을
    # 거치지 않고 학생에게 바로 노출되므로, "보기 정확히 4개" 계약을 이 상수+pad_options 로 스스로
    # 보장한다(§2b 검증 후속 [LOW/edge]).
    GENERIC_FILLER_DISTRACTORS = [ "잘 모르겠어요", "이 책과 관련이 없어요", "알 수 없어요", "관계없는 내용이에요" ].freeze

    def initialize(client: GeminiClient.new)
      @client = client
    end

    # ── 하위호환 mcq 초안(교사 퀴즈 CRUD). 반환은 count 개의 mcq 문항 해시 배열(symbol 키).
    def call(book, count: DEFAULT_COUNT, band: ReadingDomain::DEFAULT_BAND)
      return offline_mcq(book, band, count) unless @client.configured?

      response = @client.generate(
        contents: build_contents(book, count),
        system_instruction: ReadingDomain.quizgen_prompt(band),
        response_json: true
      )
      normalize_legacy(response)
    rescue GeminiClient::NotConfigured, GeminiClient::ApiError, InvalidResponse
      offline_mcq(book, band, count)
    end

    # ── Phase 2a: content_axis 세트 생성(AI→오프라인 폴백). Phase 2b GenerateGameContentJob 진입점.
    # 반환은 콘텐츠축별 문항 해시 배열(mcq=5, hint_reveal=3).
    def content_set(book, band, content_axis)
      axis = content_axis.to_sym
      return offline_set(book, band, axis) unless @client.configured?

      response = @client.generate(
        contents: build_axis_contents(book, axis),
        system_instruction: ReadingDomain.content_prompt(band, axis),
        response_json: true
      )
      normalize(response, axis, band)
    rescue GeminiClient::NotConfigured, GeminiClient::ApiError, InvalidResponse
      offline_set(book, band, axis)
    end

    # ── 책 파생 결정적 오프라인 세트(C2). 무키·즉시·결정적·무중단. 네트워크 0.
    def offline_set(book, band, content_axis)
      case content_axis.to_sym
      when :mcq          then offline_mcq(book, band, ReadingDomain::CONTENT_COUNTS[:mcq])
      when :hint_reveal  then offline_hint_reveal(book, band)
      else raise ArgumentError, "지원하지 않는 content_axis: #{content_axis.inspect}"
      end
    end

    private

    # ── AI 사용자 콘텐츠 ──────────────────────────────────────────────
    def build_contents(book, count)
      prompt = +"책 제목: #{book.title}\n"
      prompt << "지은이: #{book.author}\n" if book.author.present?
      prompt << "줄거리: #{book.summary}\n" if book.summary.present?
      prompt << "\n위 책으로 #{count}개의 4지선다 독서 퀴즈 문항을 만들어 주세요."
      [ { role: "user", parts: [ { text: prompt } ] } ]
    end

    def build_axis_contents(book, axis)
      prompt = +"책 제목: #{book.title}\n"
      prompt << "지은이: #{book.author}\n" if book.author.present?
      prompt << "줄거리: #{book.summary}\n" if book.summary.present?
      prompt << "\n위 책으로 #{ReadingDomain::CONTENT_COUNTS[axis]}개의 #{axis} 콘텐츠를 만들어 주세요."
      [ { role: "user", parts: [ { text: prompt } ] } ]
    end

    # ── 하위호환 mcq normalize(lenient: 보기 2개 이상 허용, count 미강제) ──────
    def normalize_legacy(response)
      raise InvalidResponse, "response was not a Hash" unless response.is_a?(Hash)

      questions = Array(response["questions"]).map { |raw| normalize_legacy_item(raw) }
      raise InvalidResponse, "no questions" if questions.empty?

      questions
    end

    def normalize_legacy_item(raw)
      raise InvalidResponse, "question was not a Hash" unless raw.is_a?(Hash)

      data = raw.symbolize_keys
      choices = Array(data[:choices]).map(&:to_s)
      answer_index = data[:answer_index].to_i
      prompt = data[:prompt].to_s
      raise InvalidResponse, "question needs >= 2 choices" if choices.size < 2
      raise InvalidResponse, "answer_index out of range" unless answer_index.between?(0, choices.size - 1)
      raise InvalidResponse, "prompt blank" if prompt.blank?

      mcq_hash(prompt, choices, answer_index, data[:explanation].to_s, clamp_difficulty(data[:difficulty]) || 2)
    end

    # ── content_axis별 AI normalize(count 강제·dedup·정답 검증·해설/난이도) ────
    def normalize(response, content_axis, band)
      raise InvalidResponse, "response was not a Hash" unless response.is_a?(Hash)

      case content_axis
      when :mcq          then normalize_mcq(response, band)
      when :hint_reveal  then normalize_hint_reveal(response, band)
      else raise ArgumentError, "지원하지 않는 content_axis: #{content_axis.inspect}"
      end
    end

    def normalize_mcq(response, band)
      count = ReadingDomain::CONTENT_COUNTS[:mcq]
      items = Array(response["questions"]).filter_map { |raw| normalize_mcq_item(raw, band) }
                                          .uniq { |item| item[:prompt] }
      raise InvalidResponse, "mcq needs #{count} valid questions" if items.size < count

      items.first(count)
    end

    # mcq 정답 검증: 보기 정확히 4개 + answer_index 정수 1개(범위 내). 정답 2개(배열)·범위 밖은 탈락.
    def normalize_mcq_item(raw, band)
      return nil unless raw.is_a?(Hash)

      data = raw.symbolize_keys
      prompt = data[:prompt].to_s
      choices = Array(data[:choices]).map(&:to_s)
      return nil if prompt.blank? || choices.size != 4

      index = single_index(data[:answer_index])
      return nil if index.nil? || !index.between?(0, 3)

      mcq_hash(prompt, choices, index, data[:explanation].to_s, clamp_difficulty(data[:difficulty]) || band_difficulty(band))
    end

    def normalize_hint_reveal(response, band)
      count = ReadingDomain::CONTENT_COUNTS[:hint_reveal]
      items = Array(response["targets"]).filter_map { |raw| normalize_target(raw, band) }
                                        .uniq { |item| item[:answer] }
      raise InvalidResponse, "hint_reveal needs #{count} valid targets" if items.size < count

      items.first(count)
    end

    # hint_reveal 검증: 타깃(정답) 존재 + 힌트 최소 2개.
    def normalize_target(raw, band)
      return nil unless raw.is_a?(Hash)

      data = raw.symbolize_keys
      answer = data[:answer].to_s
      hints = Array(data[:hints]).map(&:to_s).reject(&:blank?)
      return nil if answer.blank? || hints.size < 2

      {
        question_type: "hint_reveal",
        prompt: "힌트를 보고 정답을 맞혀 보세요.",
        content: { hints: hints },
        answer: answer,
        explanation: data[:explanation].to_s,
        difficulty: clamp_difficulty(data[:difficulty]) || band_difficulty(band)
      }
    end

    # ── 오프라인 결정적 세트(C2) ──────────────────────────────────────
    # mcq: 책 제목·지은이·줄거리 토큰 파생 결정적 문항. 하드코딩 오답 없음. 정답 위치는 순서로 회전.
    def offline_mcq(book, band, count)
      title = book.title.to_s
      activities = ReadingDomain.recommended_activities(band)
      codes = ReadingDomain.achievement_standards(band)
      pool = []

      pool << { prompt: "우리가 함께 읽은 책의 제목은 무엇인가요?",
                correct: title,
                distractors: [ "제목이 정해지지 않은 책", "아직 펼쳐 보지 않은 책", "다른 반이 읽은 책" ],
                explanation: "우리가 읽은 책의 제목은 「#{title}」이에요." }

      if book.author.present?
        pool << { prompt: "「#{title}」의 지은이로 알맞은 것은 무엇인가요?",
                  correct: book.author.to_s,
                  distractors: [ "여러 사람이 함께 씀", "지은이가 알려지지 않음", "출판사가 대신 씀" ],
                  explanation: "「#{title}」을(를) 쓴 사람은 #{book.author}이에요." }
      end

      pool << { prompt: "「#{title}」 같은 책을 깊이 있게 읽는 방법은 무엇일까요?",
                correct: activities[:content],
                distractors: [ "글자 수만 빠르게 세기", "그림만 넘겨 보기", "마지막 쪽만 읽기" ],
                explanation: "#{codes[:content]} 처럼 내용을 짚으며 읽어요." }

      pool << { prompt: "「#{title}」을(를) 읽고 독후감을 잘 쓰려면 어떻게 할까요?",
                correct: activities[:life],
                distractors: [ "줄거리만 길게 옮겨 적기", "느낌 없이 제목만 적기", "맞춤법을 신경 쓰지 않기" ],
                explanation: "#{codes[:life]} 처럼 삶과 연결해 써요." }

      token = salient_token(book.summary)
      if token
        pool << { prompt: "다음 중 「#{title}」의 줄거리에 나오는 낱말은 무엇인가요?",
                  correct: token,
                  distractors: summary_distractors(book.summary),
                  explanation: "「#{title}」의 줄거리에 '#{token}'(이)라는 낱말이 나와요." }
      else
        pool << { prompt: "「#{title}」을(를) 읽은 뒤 하면 좋은 활동은 무엇인가요?",
                  correct: activities[:emotion],
                  distractors: [ "교과서를 그대로 베껴 쓰기", "표지만 색칠하고 덮어 두기", "제목만 소리 내어 외우기" ],
                  explanation: "#{codes[:emotion]} 처럼 느낌을 표현해요." }
      end

      offline_mcq_extras.each { |extra| break if pool.size >= count; pool << extra }

      pool.first([ count, 1 ].max).each_with_index.map do |template, index|
        choices, answer_index = place_answer(template[:correct], template[:distractors], index)
        mcq_hash(template[:prompt], choices, answer_index, template[:explanation], band_difficulty(band))
      end
    end

    # count 가 기본 풀보다 클 때 채우는 일반 독해 문항(모두 결정적·안전).
    def offline_mcq_extras
      [
        { prompt: "책을 읽고 나서 가장 먼저 하면 좋은 것은 무엇인가요?",
          correct: "기억에 남는 장면 떠올리기",
          distractors: [ "바로 덮어 두기", "제목만 외우기", "점수만 확인하기" ],
          explanation: "기억에 남는 장면을 떠올리면 내용이 오래 남아요." },
        { prompt: "친구에게 책을 소개할 때 좋은 방법은 무엇인가요?",
          correct: "인상 깊은 까닭을 함께 말하기",
          distractors: [ "표지 색만 말하기", "쪽수만 알려 주기", "제목을 바꿔 부르기" ],
          explanation: "왜 좋았는지 까닭을 들려주면 소개가 생생해져요." }
      ]
    end

    # hint_reveal: 타깃 = 책 제목/지은이(명백히 옳은 개체) + 줄거리 토큰. 힌트는 어려움→쉬움, 안전하게 파생.
    def offline_hint_reveal(book, band)
      title = book.title.to_s
      targets = [ hint_target(title, "우리가 읽은 책의 제목이에요.", band) ]

      targets << if book.author.present?
        hint_target(book.author.to_s, "「#{title}」을(를) 쓴 사람의 이름이에요.", band)
      else
        hint_target("독후감", "책을 읽고 생각과 느낌을 쓴 글이에요.", band)
      end

      token = salient_token(book.summary)
      targets << if token
        hint_target(token, "이 책의 줄거리에 나오는 낱말이에요.", band)
      else
        hint_target("줄거리", "이야기의 중요한 내용을 간추린 것이에요.", band)
      end

      targets.first(ReadingDomain::CONTENT_COUNTS[:hint_reveal])
    end

    # 타깃 문자열 T 에 대해 항상 참인 힌트만 만든다(맥락→글자수→첫 글자, 어려움→쉬움).
    def hint_target(target, context, band)
      text = target.to_s
      hints = [
        context,
        "#{text.length}글자로 된 낱말이에요.",
        "'#{text[0]}'(으)로 시작해요."
      ]
      {
        question_type: "hint_reveal",
        prompt: "힌트를 보고 정답을 맞혀 보세요.",
        content: { hints: hints },
        answer: text,
        explanation: "정답은 '#{text}'이에요.",
        difficulty: band_difficulty(band)
      }
    end

    # ── 공통 헬퍼 ────────────────────────────────────────────────────
    def mcq_hash(prompt, choices, answer_index, explanation, difficulty)
      {
        question_type: "mcq_single",
        prompt: prompt,
        choices: choices,
        answer_index: answer_index,
        content: { prompt: prompt, choices: choices },
        answer: answer_index,
        explanation: explanation,
        difficulty: difficulty
      }
    end

    # 정답을 index 위치로 회전 배치(항상 같은 자리에 오지 않게). 보기는 항상 정확히 4개를
    # 보장한다(정답 1 + 오답 3) — 오프라인 경로는 Moderator 게시 전 검증을 거치지 않고 학생에게
    # 바로 노출되므로, 오답이 3개 미만인 경우(예: summary_distractors 가 요약에 실린 낱말이 많아
    # <3개를 반환)에도 이 함수 스스로 4개를 채워야 한다(§2b 검증 후속 [LOW/edge]).
    def place_answer(correct, distractors, index)
      options = pad_options(correct, distractors)
      answer_index = index % options.size
      choices = options.reject { |option| option == correct }
      choices.insert(answer_index, correct)
      [ choices, answer_index ]
    end

    # 오답 풀을 항상 3개 이상으로 패딩한다(부족분만 GENERIC_FILLER_DISTRACTORS 로 채움).
    def pad_options(correct, distractors)
      base = Array(distractors).map(&:to_s).reject { |d| d == correct }.uniq
      filler = GENERIC_FILLER_DISTRACTORS.reject { |d| d == correct || base.include?(d) }
      ([ correct ] + base + filler).first(4)
    end

    # answer_index 를 단일 정수로만 인정(정답 2개=배열 등은 nil → 탈락).
    def single_index(value)
      case value
      when Integer then value
      when String then (value.match?(/\A\d+\z/) ? value.to_i : nil)
      end
    end

    def clamp_difficulty(value)
      difficulty = value.to_i
      difficulty if difficulty.between?(1, 3)
    end

    def band_difficulty(band)
      BAND_DIFFICULTY.fetch(band.to_sym, 2)
    end

    # 줄거리에서 가장 긴 낱말(결정적)을 뽑는다. 그 낱말은 줄거리에 실재하므로 힌트·정답이 항상 옳다.
    def salient_token(summary)
      text = summary.to_s
      return nil if text.blank?

      tokens = text.scan(/[가-힣A-Za-z0-9]+/).select { |token| token.length >= 2 }
      tokens.max_by(&:length)
    end

    # 요약에 없는 낱말만 오답으로(정답=요약 토큰이 유일 정답이 되게).
    def summary_distractors(summary)
      text = summary.to_s
      SUMMARY_DISTRACTOR_POOL.reject { |word| text.include?(word) }.first(3)
    end
  end
end
