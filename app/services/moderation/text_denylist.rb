module Moderation
  # 결정적 한국어 금칙어 필터(무API·무네트워크). 두 소비자가 **서로 다른 리스트**를 쓴다:
  #
  #   QUIZ  — AI 생성 게임 콘텐츠(QuizModerator) 게시 전 검증용. 실패는 "게시 제외"(비파괴,
  #           오프라인 세트 유지)라 오탐 비용이 낮아 보수적으로 넓게 둔다. 기존 동작을 그대로
  #           보존해야 하므로 QuizModerator::DENYLIST 원본과 동일하다.
  #   FORUM — 학생 자유입력(토론 글) 저장 검증용. 실패는 "저장 거부"(대면 실패)라 오탐 비용이
  #           크다. `새끼`(곰 새끼)·`꺼져`(불이 꺼져) 처럼 정상 표현에 부분일치하는 낱말을 빼고
  #           명백한 욕설만 하드블록한다. 잔여는 신고·교사 모더레이션으로 사후 회수(정직화).
  #
  # 매칭은 부분 문자열(`include?`) — 한국어는 공백 토큰화가 불완전해 단어경계가 불명확하기 때문.
  # 그래서 FORUM 리스트는 부분일치해도 안전한(정상어에 안 걸리는) 낱말만 남기는 방식으로 오탐을 막는다.
  class TextDenylist
    QUIZ = %w[씨발 시발 개새끼 새끼 지랄 좆 병신 강간 자살해 죽여버 꺼져].freeze
    FORUM = %w[씨발 시발 개새끼 지랄 좆 병신 강간 자살해 죽여버].freeze

    # text 안에서 list 의 금칙어를 부분일치로 찾아 매칭된 낱말 배열을 반환한다(없으면 []).
    def self.hits(text, list: QUIZ)
      haystack = text.to_s
      list.select { |word| haystack.include?(word) }
    end

    # 금칙어가 하나라도 있으면 true.
    def self.flagged?(text, list: QUIZ)
      hits(text, list: list).any?
    end
  end
end
