# 학생 출제 기여(전국 공유 문제은행 UGC, 게임 재구성 Phase 3 §4). 학생이 그 책의 문제를 내면
# pending 으로 담임 검토 큐에 쌓이고, 담임이 내용 수정·밴드 지정·승인하면
# Games::ContributionPublisher 가 system·global·band 풀 퀴즈로 물질화한다(전국 편입).
# 승인 전까지는 Quiz/풀 밖의 pending 행이라 아무에게도 노출되지 않는다.
#
# content_axis 는 콘텐츠축 2종(mcq=독서 퀴즈 / hint_reveal=나는 누구게?)만 대상이며,
# payload 는 축별 문항 페이로드 JSON 이다:
#   mcq         : { prompt, choices[4], answer_index, explanation }
#   hint_reveal : { answer, hints[≥2], explanation }
# 검증은 축별 페이로드 유효성 + 금칙어(Moderation::TextDenylist::QUIZ). status 는 pending 시작.
class QuizContribution < ApplicationRecord
  belongs_to :user
  belongs_to :book
  belongs_to :classroom
  belongs_to :reviewed_by, class_name: "User", optional: true

  # content_axis 정수 매핑은 이 모델 전용(Quiz.content_axis 정수 의존 없음 — 물질화 때 심볼명으로 넘긴다).
  enum :content_axis, { mcq: 0, hint_reveal: 1 }
  enum :band, { g12: 0, g34: 1, g56: 2 }
  enum :status, { pending: 0, approved: 1, rejected: 2 }, default: :pending

  validate :payload_shape
  validate :payload_clean

  # 페이로드를 심볼/문자열 키 무관하게 읽는다(방금 build 된 행·DB 재조회 행 양쪽 동작).
  def payload_hash
    (payload || {}).with_indifferent_access
  end

  private

  # 축별 페이로드가 채점 가능한 형태인지 검증한다(mcq 보기4·정답인덱스 범위, hint_reveal 정답+힌트≥2).
  def payload_shape
    data = payload_hash
    case content_axis
    when "mcq"
      choices = Array(data[:choices]).map { |c| c.to_s.strip }.reject(&:blank?)
      errors.add(:payload, "질문을 입력해 주세요.") if data[:prompt].to_s.strip.blank?
      errors.add(:payload, "보기를 4개 입력해 주세요.") unless choices.size == 4
      index = data[:answer_index]
      errors.add(:payload, "정답 보기를 골라 주세요.") unless index.is_a?(Integer) && index.between?(0, 3)
    when "hint_reveal"
      hints = Array(data[:hints]).map { |h| h.to_s.strip }.reject(&:blank?)
      errors.add(:payload, "정답을 입력해 주세요.") if data[:answer].to_s.strip.blank?
      errors.add(:payload, "힌트를 2개 이상 입력해 주세요.") if hints.size < 2
    else
      errors.add(:content_axis, "은(는) 지원하지 않는 문제 유형이에요.")
    end
  end

  # 금칙어(QUIZ 리스트) — 게임 콘텐츠 게시 전 검증과 동일 리스트로 학생 입력을 걸러낸다.
  def payload_clean
    combined = payload_hash.values_at(:prompt, :answer, :explanation).map(&:to_s)
    combined += Array(payload_hash[:choices]).map(&:to_s)
    combined += Array(payload_hash[:hints]).map(&:to_s)
    return unless Moderation::TextDenylist.flagged?(combined.join(" "), list: Moderation::TextDenylist::QUIZ)

    errors.add(:payload, "사용할 수 없는 표현이 들어 있어요. 고운 말로 고쳐 주세요.")
  end
end
