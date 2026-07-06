module Ai
  # 외부 호출 없는 규칙기반 5축 첨삭(무중단 폴백). 키가 없거나 LLM 호출이
  # 실패해도 항상 성공하며, LLM 경로와 동일한 해시 형태를 반환한다.
  class RuleBasedReview
    FEELING_WORDS = %w[느꼈 느낀 느낌 생각 감동 슬펐 기뻤 재미 인상 감정 마음 좋았 행복 놀랐 뭉클].freeze
    LIFE_WORDS = %w[나의 우리 삶 경험 나는 내가 저는 스스로 다짐 반성 실천 우리의 나에게].freeze

    # body 로 5축 점수를 산출하고 RubricScorable 로 등급·포인트를 결정한다.
    # 반환: { level:, rubric:, praise:, fix:, grow:, pts: } (LLM 경로와 동형).
    def call(body:, book_title: nil)
      text = body.to_s
      rubric = {
        content: content_score(text),
        emotion: emotion_score(text),
        life: life_score(text),
        structure: structure_score(text),
        spelling: spelling_score(text)
      }

      result = RubricScorable.score_rubric(rubric)
      {
        level: result[:level],
        rubric: rubric,
        praise: praise_for(rubric),
        fix: fix_for(rubric),
        grow: grow_for(rubric),
        pts: result[:points]
      }
    end

    private

    def content_score(text)
      length = text.strip.length
      case
      when length >= 400 then 5
      when length >= 250 then 4
      when length >= 150 then 3
      when length >= 60 then 2
      when length >= 1 then 1
      else 0
      end
    end

    def structure_score(text)
      sentences = text.split(/[.!?。\n]+/).map(&:strip).reject(&:empty?)
      case sentences.size
      when 0 then 0
      when 1 then 1
      when 2 then 2
      when 3, 4 then 3
      when 5, 6, 7 then 4
      else 5
      end
    end

    def emotion_score(text)
      return 0 if text.strip.empty?

      hits = FEELING_WORDS.count { |word| text.include?(word) }
      [ 1 + hits, 5 ].min
    end

    def life_score(text)
      return 0 if text.strip.empty?

      hits = LIFE_WORDS.count { |word| text.include?(word) }
      [ 1 + hits, 5 ].min
    end

    def spelling_score(text)
      length = text.strip.length
      case
      when length.zero? then 0
      when length >= 60 then 4
      when length >= 20 then 3
      else 2
      end
    end

    def praise_for(rubric)
      rubric.select { |_axis, score| score >= 4 }.map do |axis, _score|
        "#{ReadingDomain::AXIS_LABELS[axis]}이(가) 훌륭해요."
      end
    end

    def fix_for(rubric)
      rubric.select { |_axis, score| score <= 2 }.map do |axis, _score|
        "#{ReadingDomain::AXIS_LABELS[axis]}을(를) 조금 더 보완해 볼까요?"
      end
    end

    def grow_for(rubric)
      weakest = rubric.min_by(2) { |_axis, score| score }
      weakest.map do |axis, _score|
        {
          text: "#{ReadingDomain::AXIS_LABELS[axis]}을(를) 키우면 글이 한층 좋아져요.",
          standard_code: ReadingDomain::ACHIEVEMENT_STANDARDS[axis]
        }
      end
    end
  end
end
