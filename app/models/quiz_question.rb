# 퀴즈 문항(P5.6 → Phase 1 다형화). question_type 으로 4종 채점타입을 표현한다.
#   mcq_single  : choices 보기 배열 + answer_index 정답(하위호환).
#   mcq_multi   : content 보기 + answer 정답 인덱스 배열.
#   matching    : content 좌/우 항목 + answer 쌍맵(좌 인덱스 → 우 인덱스).
#   hint_reveal : content 힌트 배열 + answer 타깃(정답). 채점은 서버 힌트 공개수 기반(§3.2b).
class QuizQuestion < ApplicationRecord
  belongs_to :quiz

  # 정수 백엔드 enum(명시 매핑 고정). content_axis(3값)와 달리 채점타입은 4값 —
  # mcq content_axis 안에서도 mcq_single/mcq_multi 두 채점타입이 존재한다.
  enum :question_type, { mcq_single: 0, mcq_multi: 1, matching: 2, hint_reveal: 3 },
       default: :mcq_single
  # source: manual(교사 수기)·ai(워밍 게시)·offline(결정적 폴백)·contributed(학생 기여 승인, Phase 3 §4 additive).
  # curated(시드 큐레이션 문항, Stage 2 additive — db/seeds/book_quizzes.yml 검수 문항의 물질화).
  # 정수 매핑 고정 — 재배열 금지(과거 기록·집계 안정성).
  enum :source, { manual: 0, ai: 1, offline: 2, contributed: 3, curated: 4 }, default: :manual

  # 첫 AR 검증(Phase 1 §1.2). question_type presence + 타입별 정답 유효성.
  validates :question_type, presence: true
  validate :answer_shape

  # 제출된 보기 인덱스가 정답과 일치하는지(mcq_single 하위호환).
  def correct?(selected_index)
    !answer_index.nil? && selected_index.to_i == answer_index
  end

  # 안전한 보기 배열(nil → []).
  def choice_list
    Array(choices)
  end

  # content(JSON)를 심볼/문자열 키 무관하게 읽는다. 방금 build 된 행(심볼 키)과 DB 재조회
  # 행(문자열 키) 양쪽에서 뷰가 동일하게 동작하도록 indifferent access 로 감싼다(§3.2a).
  def content_hash
    (content || {}).with_indifferent_access
  end

  # hint_reveal: 힌트 배열(어려움→쉬움). matching: 좌/우 항목.
  def hints_list
    Array(content_hash[:hints])
  end

  def match_lefts
    Array(content_hash[:lefts])
  end

  def match_rights
    Array(content_hash[:rights])
  end

  # 타입별 채점을 QuestionScorer 에 위임한다(§1.2). hint_reveal 은 서버 권위 힌트수를 받는다.
  def score_for(response, hints_used: 0)
    Games::QuestionScorer.for(self).score(response, hints_used: hints_used)
  end

  # 폼 입력용 1-based 정답 번호. 저장은 0-based(answer_index) 불변.
  def answer_number
    answer_index.nil? ? nil : answer_index + 1
  end

  def answer_number=(value)
    self.answer_index = value.blank? ? nil : value.to_i - 1
  end

  private

  # 타입별 정답 표현이 채점 가능한 형태인지 검증한다. 무효 정답이 채점기로 흘러가는 것을 막는다.
  def answer_shape
    case question_type
    when "mcq_single"
      errors.add(:answer_index, "은(는) mcq_single 문항에 필요합니다") if answer_index.nil?
    when "mcq_multi"
      errors.add(:answer, "은(는) 정답 인덱스 배열이어야 합니다") unless answer.is_a?(Array) && answer.any?
    when "matching"
      errors.add(:answer, "은(는) 비어있지 않은 쌍맵이어야 합니다") unless answer.is_a?(Hash) && answer.any?
    when "hint_reveal"
      errors.add(:answer, "은(는) 타깃 정답이 있어야 합니다") if answer.blank?
    end
  end
end
