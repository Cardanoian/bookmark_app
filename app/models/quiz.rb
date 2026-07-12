# 독서 퀴즈(P5.6). 교사/총괄이 출제하고 published 플래그로 학생 노출을 통제한다.
# scope classroom(학급 한정) / global(전역). 문항은 position 순서로 재생된다.
class Quiz < ApplicationRecord
  belongs_to :created_by, class_name: "User"
  belongs_to :book, optional: true
  belongs_to :classroom, optional: true

  has_many :quiz_questions, -> { order(:position) }, dependent: :destroy, inverse_of: :quiz
  has_many :quiz_attempts, dependent: :destroy

  accepts_nested_attributes_for :quiz_questions, allow_destroy: true

  enum :scope, { classroom: 0, global: 1 }

  # 콘텐츠축·학년군·출처(Phase 1 §1.1·§1.3). 정수 백엔드 enum 을 명시 매핑으로 고정한다 —
  # Phase 2b 부분 유니크 인덱스의 정수 술어(origin=system)와 point_award 콘텐츠축 상한
  # 조회가 이 정수값에 의존하므로 값을 재배열하지 말 것.
  #   content_axis : 캐시·dedup·채점 스케일 키(4값). teacher 퀴즈는 nil 허용.
  #   band         : 학년군(성취기준 눈높이 = 상한 비교 경계).
  #   origin       : teacher(per-quiz 멱등) / system(콘텐츠축 캐시). scopes:false —
  #                  Quiz.system 스코프는 만들지 않고 Quiz.origins[:system] 해시만 쓴다.
  enum :content_axis, { mcq: 0, matching: 1, hint_reveal: 2, balance_vote: 3 }
  enum :band, { g12: 0, g34: 1, g56: 2 }
  enum :origin, { teacher: 0, system: 1 }, default: :teacher, scopes: false
  enum :generation_status, { ready: 0, warming: 1, failed: 2 }, default: :ready

  validates :title, presence: true

  scope :published, -> { where(published: true) }
end
