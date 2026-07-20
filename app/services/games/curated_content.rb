module Games
  # 큐레이션 게임 문항 서빙 헬퍼(Stage 2). CuratedQuiz(Sonnet 팀 검수 문항)를 조회해 균일 문항
  # 해시 배열로 변환한다. Games::ContentProvider 가 큐레이션 우선 서빙·워밍 억제·가용성 게이트에서
  # 이 헬퍼로 "그 책·축에 큐레이션이 있는지"를 판정하고, MISS 물질화 시 set_for 로 검수 문항을 얻는다.
  #
  # 변환 규약은 QuizDraftService#mcq_hash/normalize_target·ContributionPublisher 와 동형이라
  # 반환 해시를 ContentProvider.build_questions/question_attributes 가 그대로 소비한다(키 이름 일치).
  module CuratedContent
    module_function

    # 그 책·축에 큐레이션 문항이 있는가(큐레이션 우선·워밍 억제·가용성 게이트 판정용).
    def available?(book, content_axis)
      book && CuratedQuiz.exists?(book_id: book.id, content_axis: content_axis.to_s)
    end

    # 그 책에 어느 축이든 큐레이션이 있는가(seed 최초 도입 판정 등 축 무관 조회용).
    def available_for_any_axis?(book)
      book && CuratedQuiz.exists?(book_id: book.id)
    end

    # 그 책·축의 payload 를 균일 문항 해시 배열로 변환해 반환한다(없으면 nil). 반환 해시는
    # ContentProvider.build_questions 가 그대로 소비한다(QuizDraftService 오프라인 세트와 동형).
    def set_for(book, content_axis)
      return nil unless book

      curated = CuratedQuiz.find_by(book_id: book.id, content_axis: content_axis.to_s)
      return nil unless curated

      Array(curated.payload).map do |raw|
        item = raw.with_indifferent_access
        case curated.content_axis
        when "mcq"         then mcq_hash(item)
        when "hint_reveal" then hint_reveal_hash(item)
        end
      end
    end

    # mcq item → 균일 mcq_single 해시(하위호환 choices/answer_index 병기).
    def mcq_hash(item)
      choices = Array(item[:choices]).map(&:to_s)
      answer_index = item[:answer_index].to_i
      prompt = item[:prompt].to_s
      {
        question_type: "mcq_single",
        prompt: prompt,
        choices: choices,
        answer_index: answer_index,
        content: { prompt: prompt, choices: choices },
        answer: answer_index,
        explanation: item[:explanation].to_s,
        difficulty: item[:difficulty]
      }
    end

    # hint_reveal item → 균일 hint_reveal 해시.
    def hint_reveal_hash(item)
      hints = Array(item[:hints]).map(&:to_s).reject(&:blank?)
      {
        question_type: "hint_reveal",
        prompt: "힌트를 보고 정답을 맞혀 보세요.",
        content: { hints: hints },
        answer: item[:answer].to_s,
        explanation: item[:explanation].to_s,
        difficulty: item[:difficulty]
      }
    end
  end
end
