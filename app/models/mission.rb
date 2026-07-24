# 학급 단위 독서 미션(menu_refactor 심화 §2.A). 기간·정량 목표·자동 배정·정확히-1회 포인트
# 보상으로 재설계된다. 발행 생명주기는 status enum(draft/published/cancelled/archived)으로 관리하고,
# 완료 판정의 단일 진실은 mission_participations.completed_at 이다(PR2 에서 ReadingStats#missions 전환).
# 레거시 book_id 컬럼은 PR6 에서 드롭했다(특정 도서 목표는 후속 goal_type 으로 다룬다).
class Mission < ApplicationRecord
  # 보상 상한 폴백(AppSetting "mission_reward_max_points" 미설정/무효 시).
  DEFAULT_REWARD_MAX_POINTS = 200

  belongs_to :classroom
  belongs_to :created_by, class_name: "User", optional: true

  has_many :mission_goals, dependent: :destroy
  has_many :mission_participations, dependent: :destroy

  enum :status, { draft: 0, published: 1, cancelled: 2, archived: 3 }, default: :draft

  validates :title, presence: true, length: { in: 1..80 }
  validates :start_date, :end_date, presence: true
  validates :reward_points, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: ->(_mission) { Mission.reward_max_points }
  }
  validate :end_date_not_before_start_date
  validate :published_requires_goal

  # 보상 상한(AppSetting 조회, 무효/미설정 시 기본값 200). 서버가 항상 재검증하는 단일 진실.
  def self.reward_max_points
    value = AppSetting.get("mission_reward_max_points").to_i
    value.positive? ? value : DEFAULT_REWARD_MAX_POINTS
  end

  # 발행됐고 아직 시작 전(오늘 < 시작일).
  def scheduled?
    published? && start_date.present? && Date.current < start_date
  end

  # 발행됐고 기간 내(시작일 <= 오늘 <= 종료일).
  def active?
    published? && start_date.present? && end_date.present? &&
      start_date <= Date.current && Date.current <= end_date
  end

  # 발행됐고 종료일이 지남(오늘 > 종료일).
  def ended?
    published? && end_date.present? && Date.current > end_date
  end

  # draft → published 전환 + 학급 학생 자동 배정(menu_refactor 심화 §10.2). 검증(목표≥1) 실패 시
  # errors 를 채우고 false 를 반환한다(예외 없음 — 호출부가 분기). 배정·즉시 평가·방송은 상태 저장
  # 커밋 후(AssignmentSync)로 분리한다.
  def publish!
    return false unless draft?

    self.status = :published
    self.published_at = Time.current
    return false unless save

    Missions::AssignmentSync.on_publish(self)
    true
  end

  private

  def end_date_not_before_start_date
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, "은 시작일보다 빠를 수 없습니다") if end_date < start_date
  end

  # 발행하려면 목표가 1개 이상 있어야 한다(빈 미션 발행 방지, Rewarder m6 가드와 짝).
  def published_requires_goal
    return unless published?

    errors.add(:base, "발행하려면 목표를 1개 이상 추가하세요") if mission_goals.empty?
  end
end
