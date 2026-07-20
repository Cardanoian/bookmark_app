module Games
  # 학생 기여 승인 → 전국 공유 풀 편입(게임 재구성 Phase 3 §4.4). 담임이 수정·승인한 최종
  # 페이로드를 **system-scope·global·band-keyed 풀 퀴즈로 물질화**한다. 구체적으로 `(book, band,
  # content_axis)` 에 대해 origin: system·scope: global·published·ready 인 Quiz 를 새 content_version 으로
  # 만들고, 그 quiz_questions 에 기여 문항을 `source: :contributed` 로 추가한다(ContentProvider.build_questions
  # 재사용). system origin 은 이미 within_band=전국 공유(§3.5)라, 이렇게 하면 **QuizPolicy·PointAward·
  # fetch_ready 무변경으로 자동으로 전국 풀에 편입**된다(다른 학교 학생도 같은 밴드면 플레이 풀에서 만난다).
  #
  # 한 승인 = (book, band, axis) 풀에 새 세트 1개(문항 1개) 추가. 세트 단위 랜덤 출제(§3.5)의 후보가 된다.
  class ContributionPublisher
    # 승인 시 부여 난이도(band 파생). QuizDraftService 오프라인 세트와 스케일 일치.
    BAND_DIFFICULTY = { "g12" => 1, "g34" => 2, "g56" => 3 }.freeze

    # 동시 워밍 잡과의 content_version 선점 경쟁(RecordNotUnique) 유한 재시도 상한.
    VERSION_RACE_RETRY_LIMIT = 3

    def self.publish!(contribution)
      new(contribution).publish!
    end

    def initialize(contribution)
      @contribution = contribution
    end

    # 물질화된 published·ready system Quiz 를 반환한다. 동시 선점 경쟁은 유한 재시도로 흡수.
    def publish!
      attempts = 0
      begin
        build_and_save
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < VERSION_RACE_RETRY_LIMIT
        raise
      end
    end

    private

    def build_and_save
      quiz = build_quiz
      ContentProvider.build_questions(quiz, [ question_hash ], source: :contributed)
      quiz.tap(&:save!)
    end

    def build_quiz
      axis = @contribution.content_axis
      band = @contribution.band
      Quiz.new(
        title: "기여 #{axis}",
        created_by: ContentProvider.system_user,
        book: @contribution.book,
        scope: :global, published: true, origin: :system,
        content_axis: axis, band: band,
        content_version: next_version(@contribution.book_id, band, axis),
        generation_status: :ready
      )
    end

    def next_version(book_id, band, axis)
      Quiz.where(origin: :system, book_id: book_id, band: band, content_axis: axis)
          .maximum(:content_version).to_i + 1
    end

    # 축별 페이로드 → 균일 문항 해시(QuizDraftService 산출과 동형; build_questions 가 소비).
    def question_hash
      data = @contribution.payload_hash
      difficulty = BAND_DIFFICULTY[@contribution.band]
      case @contribution.content_axis
      when "mcq"        then mcq_hash(data, difficulty)
      when "hint_reveal" then hint_reveal_hash(data, difficulty)
      else raise ArgumentError, "지원하지 않는 content_axis: #{@contribution.content_axis.inspect}"
      end
    end

    def mcq_hash(data, difficulty)
      choices = Array(data[:choices]).map(&:to_s)
      answer_index = data[:answer_index].to_i
      prompt = data[:prompt].to_s
      {
        question_type: "mcq_single",
        prompt: prompt,
        choices: choices,
        answer_index: answer_index,
        content: { prompt: prompt, choices: choices },
        answer: answer_index,
        explanation: data[:explanation].to_s,
        difficulty: difficulty
      }
    end

    def hint_reveal_hash(data, difficulty)
      hints = Array(data[:hints]).map(&:to_s).reject(&:blank?)
      {
        question_type: "hint_reveal",
        prompt: "힌트를 보고 정답을 맞혀 보세요.",
        content: { hints: hints },
        answer: data[:answer].to_s,
        explanation: data[:explanation].to_s,
        difficulty: difficulty
      }
    end
  end
end
