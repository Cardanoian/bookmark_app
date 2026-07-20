module Ai
  # 외부 호출 없는 규칙기반 뒷이야기 격려 코멘트(무중단 폴백). 키가 없거나 LLM 호출이 실패해도
  # 항상 성공하며, 학생의 노력(글 길이)에 맞춘 **항상 긍정적인** 격려 코멘트 문자열을 반환한다.
  # 점수·등급을 매기지 않고, 다음 글을 쓰고 싶어지도록 따뜻하게 말한다(초등 전학년 눈높이).
  class RuleBasedSequelFeedback
    SUGGESTION = "다음에는 주인공의 마음이 어땠을지 한 문장만 더 상상해서 적어 볼까요?".freeze

    # body 로 격려 코멘트를 산출한다(book_title 은 맥락 표시용, 선택). 반환: 코멘트 문자열(항상 유효).
    def call(body:, book_title: nil)
      "#{praise_for(body.to_s.strip.length)} #{SUGGESTION}"
    end

    private

    def praise_for(length)
      case
      when length >= 300 then "이야기를 이렇게 길게 이어 쓰다니 상상력이 정말 대단해요!"
      when length >= 120 then "책 뒤에 이어질 이야기를 멋지게 상상해서 써 주었어요."
      when length >= 1   then "짧지만 너만의 상상이 담긴 이야기라 반가워요."
      else "이야기를 시작해 준 것만으로도 멋져요."
      end
    end
  end
end
