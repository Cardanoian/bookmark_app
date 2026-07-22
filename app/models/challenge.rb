# 전역/학교 단위 챌린지. 미션처럼 정량 목표(독후감 수·게임 수, 목표별 선택 도서)와 정확히-1회
# 포인트 보상을 가질 수 있다(챌린지 목표화 — 미션 서브시스템 미러). 목표가 없는 챌린지는 기존
# join 방식(참여 report.challenge_id → 랭킹)만 동작한다(목표·보상은 additive).
#
# scope·school_id 는 사용자 폼 입력이 아니라 관리자 역할에서 파생한다(ChallengesController#apply_scope_from_role):
# 총괄관리자=전국(global), 교사·사서·교무=우리 학교(school, 본인 school_id).
#
# description(소개글)은 미션과 대칭인 선택 입력이라 별도 검증을 두지 않는다(빈 값 허용).
class Challenge < ApplicationRecord
  # 보상 상한 폴백(AppSetting "challenge_reward_max_points" 미설정/무효 시). 미션(200)보다 큰
  # 전국/학교 스코프라 상한을 조금 높게 둔다.
  DEFAULT_REWARD_MAX_POINTS = 300

  enum :scope, { global: 0, school: 1 }

  belongs_to :school, optional: true

  has_many :challenge_goals, dependent: :destroy
  has_many :challenge_participations, dependent: :destroy

  validates :title, presence: true
  validates :school_id, presence: true, if: :school?
  validates :reward_points, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: ->(_challenge) { Challenge.reward_max_points }
  }

  # 보상 상한(AppSetting 조회, 무효/미설정 시 기본값). 서버가 항상 재검증하는 단일 진실.
  def self.reward_max_points
    value = AppSetting.get("challenge_reward_max_points").to_i
    value.positive? ? value : DEFAULT_REWARD_MAX_POINTS
  end

  # 목표 1개 이상 = 진행·보상 대상(목표 없으면 레거시 join 챌린지).
  def has_goals?
    challenge_goals.any?
  end

  # 진행 집계 창의 시작일. starts_on 미지정이면 생성일을 바닥으로 삼아(과거 활동 소급 완료 방지)
  # 챌린지가 생긴 뒤의 활동만 인정한다.
  def window_start
    starts_on || created_at.to_date
  end

  # 진행 집계 창의 종료일(nil = 상한 없음, 계속 진행).
  def window_end
    ends_on
  end

  # 주어진 날짜가 진행 창 안인지. 목표 활동 인정·활성 판정의 단일 기준.
  def within_window?(date)
    return false if date.nil?
    return false if window_start && date < window_start

    window_end.nil? || date <= window_end
  end

  # 오늘 기준 활성(기간 내).
  def active?
    within_window?(Date.current)
  end
end
