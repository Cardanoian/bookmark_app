# 독서 퀴즈(P5.6). 교사/총괄이 출제하고 published 플래그로 학생 노출을 통제한다.
# scope classroom(학급 한정) / global(전역). 문항은 position 순서로 재생된다.
class Quiz < ApplicationRecord
  belongs_to :created_by, class_name: "User"
  belongs_to :book, optional: true
  belongs_to :classroom, optional: true

  has_many :quiz_questions, -> { order(:position) }, dependent: :destroy, inverse_of: :quiz
  has_many :quiz_attempts, dependent: :destroy
  has_many :quiz_reports, dependent: :destroy

  accepts_nested_attributes_for :quiz_questions, allow_destroy: true

  enum :scope, { classroom: 0, global: 1 }

  # 콘텐츠축·학년군·출처(Phase 1 §1.1·§1.3). 정수 백엔드 enum 을 명시 매핑으로 고정한다 —
  # Phase 2b 부분 유니크 인덱스의 정수 술어(origin=system)와 point_award 콘텐츠축 상한
  # 조회가 이 정수값에 의존하므로 값을 재배열하지 말 것.
  #   content_axis : 캐시·dedup·채점 스케일 키(3값). teacher 퀴즈는 nil 허용.
  #   band         : 학년군(성취기준 눈높이 = 상한 비교 경계).
  #   origin       : teacher(per-quiz 멱등) / system(콘텐츠축 캐시). scopes:false —
  #                  Quiz.system 스코프는 만들지 않고 Quiz.origins[:system] 해시만 쓴다.
  enum :content_axis, { mcq: 0, matching: 1, hint_reveal: 2 }
  enum :band, { g12: 0, g34: 1, g56: 2 }
  enum :origin, { teacher: 0, system: 1 }, default: :teacher, scopes: false
  enum :generation_status, { ready: 0, warming: 1, failed: 2 }, default: :ready

  validates :title, presence: true

  scope :published, -> { where(published: true) }

  # 객관식 채점타입(mcq 콘텐츠축 안의 두 가지).
  MCQ_QUESTION_TYPES = %w[mcq_single mcq_multi].freeze

  # 이 퀴즈를 마쳤을 때 완료 원장(GamePlay)에 남길 게임 종류. **요청값이 아니라 검증한 퀴즈 유형에서**
  # 정한다 — 객관식 제출에 game 값만 바꿔 보내 5종 완료 기록을 만들던 조작을 막는다(BUG_FIX_PLAN F4).
  # 제출 컨트롤러(안내·이동 경로)와 채점 서비스(원장 기록)가 이 한 곳의 결과를 함께 쓴다.
  #   mcq 축, 또는 축을 저장하지 않는 교사 퀴즈 → "quiz"(문항이 모두 객관식일 때)
  #   hint_reveal 축                          → "whoami"(문항이 모두 hint_reveal 일 때)
  #   matching(휴면)·알 수 없는 축·축과 문항 구성이 어긋난 퀴즈·문항 없는 퀴즈 → nil(제출을 받지 않는다)
  def play_game_type
    types = quiz_questions.map(&:question_type).uniq
    return nil if types.empty?

    if hint_reveal?
      "whoami" if types == %w[hint_reveal]
    elsif mcq? || (content_axis.nil? && origin == "teacher")
      "quiz" if (types - MCQ_QUESTION_TYPES).empty?
    end
  end
end
