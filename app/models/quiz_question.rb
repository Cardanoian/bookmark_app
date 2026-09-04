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
  # 보기 중복 금지. **변경된 문항만** 검증한다 — AI·시드 유래 레거시 행에 중복이 있어도
  # 질문만 고치는 저장이 막히면 안 된다(실사 결과 현재 위반 0/121 이지만 미래 입력이 남는다).
  validate :choices_are_distinct, if: :choices_changed?
  # mcq 정답 인덱스가 실제 보기 범위 안인지. answer_shape 가 이미 presence 를 보므로
  # 여기서 다시 보지 않는다(같은 오류가 배너에 두 번 뜨지 않게).
  validate :answer_indexes_within_choices, if: -> { mcq_single? || mcq_multi? }

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
  # **제거하지 말 것** — 학생 기여(quiz_contributions)·총괄 폼이 계속 이 접근자를 쓴다.
  def answer_number
    answer_index.nil? ? nil : answer_index + 1
  end

  def answer_number=(value)
    self.answer_index = value.blank? ? nil : value.to_i - 1
  end

  # 폼 입력용 정답 인덱스 배열(0-based). 체크박스 UI 와 짝이며, 고른 개수로 채점타입까지 확정한다:
  # 1개 이하 → mcq_single(answer_index), 2개 이상 → mcq_multi(answer 배열).
  def answer_indexes
    mcq_multi? ? Array(answer).map(&:to_i) : Array(answer_index).compact
  end

  # **mcq 계열에만 동작한다.** hint_reveal·matching 문항에는 no-op 이다 — 그 문항들은
  # `answer` 에 정답 문자열·쌍맵을 담는데, 가드가 없으면 체크 0개(hidden sentinel 만 전송)일 때
  # question_type 을 mcq_single 로 덮고 answer 를 날려 저장 자체가 불가능해진다(총괄 화면은
  # 타입을 가리지 않고 전 퀴즈를 편집하며 hint_reveal 문항이 실재한다).
  #
  # `new_record?` 를 가드에 넣지 않는다 — `question_type` 의 DB 기본값이 0(mcq_single)이라
  # `QuizQuestion.new` 은 이미 `mcq_single?` 가 true 다. 넣으면 오히려
  # `new(question_type: :hint_reveal, answer_indexes: [...])` 처럼 한 해시에 함께 대입될 때
  # 가드가 무조건 통과해 정답을 덮고, 대입 순서에 따라 결과가 갈리는 비결정성이 생긴다.
  def answer_indexes=(values)
    return unless mcq_single? || mcq_multi?

    indexes = Array(values).reject { |v| v.to_s.strip.empty? }.map(&:to_i).uniq.sort
    if indexes.size >= 2
      self.question_type = :mcq_multi
      self.answer_index  = nil
      self.answer        = indexes
    else
      self.question_type = :mcq_single
      self.answer_index  = indexes.first
      # mcq_single 도 answer 에 정답을 병기한다 — AI 초안·시드·기여 승격이 이미 쓰는 관례다
      # (quiz_draft_service·curated_content·contribution_publisher). McqSingle 채점기는 answer 를
      # 읽지 않으므로 채점에는 영향이 없고, 표현만 세 경로와 일치시킨다.
      self.answer        = indexes.first
    end
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

  # 같은 보기를 두 번 넣으면 정답이 둘 중 어느 쪽인지 정할 수 없고, 학생 화면에는 똑같은 칸이
  # 두 개 뜬다. 앞뒤 공백만 다른 것도 같은 보기로 본다(squish 후 비교).
  def choices_are_distinct
    normalized = choice_list.map { |choice| choice.to_s.squish }.reject(&:blank?)
    return if normalized.uniq.size == normalized.size

    errors.add(:choices, "는 서로 달라야 해요(같은 보기를 두 번 넣을 수 없어요)")
  end

  def answer_indexes_within_choices
    size = choice_list.size
    return if size.zero?

    out_of_range = answer_indexes.reject { |index| index.between?(0, size - 1) }
    return if out_of_range.empty?

    errors.add(:answer, "이 보기 범위를 벗어났어요(보기 #{size}개)")
  end
end
