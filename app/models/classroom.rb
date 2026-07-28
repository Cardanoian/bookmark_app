class Classroom < ApplicationRecord
  # 가중치 기본값의 단일 진실은 ReadingDomain 이다(도메인 상수는 코드 한곳에 둔다는 규칙).
  # 같은 해시를 여기서 다시 리터럴로 적어 두면 한쪽만 고쳐졌을 때 신규 학급의 rubric_config 와
  # 가중치 미설정 학급의 채점 기준이 조용히 갈린다. 별칭으로만 둔다.
  DEFAULT_RUBRIC_WEIGHTS = ReadingDomain::DEFAULT_RUBRIC_WEIGHTS

  belongs_to :school
  belongs_to :teacher, class_name: "User", optional: true
  has_many :users, dependent: :nullify
  has_many :reports, dependent: :destroy
  has_many :missions, dependent: :destroy

  # 학급은 (학교·학년도·학년·반) 4튜플로 유일하다. academic_year 를 스코프에 포함해
  # 같은 학교의 같은 학년·반을 학년도별로 공존시킨다(2026학년도 3-1 vs 2027학년도 3-1).
  validates :class_no, uniqueness: { scope: [ :school_id, :academic_year, :grade ] }
  validates :academic_year, presence: true,
                            numericality: { only_integer: true, greater_than: 2000, less_than: 3000 }

  before_validation :apply_default_academic_year, on: :create
  before_validation :inject_default_rubric_config, on: :create

  # 현재 학년도(한국 KST 기준). 3월부터 새 학년도이므로 1·2월은 전년도를 반환한다.
  # 로그인·학급개설 폼 기본값과 시드·모델 기본값의 단일 진실. 서버 전역 time_zone 설정에
  # 의존하지 않도록 KST 로 명시 변환한다(1·2월 경계의 UTC 드리프트 방지).
  def self.current_academic_year(today = Time.current.in_time_zone("Asia/Seoul").to_date)
    today.month <= 2 ? today.year - 1 : today.year
  end

  def label
    "#{grade}학년 #{class_no}반"
  end

  # 학년도를 앞에 붙인 레이블(교차 학년도 구분이 필요한 화면 전용 — 기본 label 은 회귀 방지로 불변).
  def label_with_year
    "#{academic_year}학년도 #{label}"
  end

  def rubric_weights
    weights = rubric_config&.dig("weights")
    return DEFAULT_RUBRIC_WEIGHTS.dup if weights.blank?

    weights.symbolize_keys
  end

  def rubric_emphasis
    rubric_config&.dig("emphasis")
  end

  private

  # 학년도를 지정하지 않고 생성하면 현재 학년도로 기본 세팅한다(교사 가입 폼은 명시 전달).
  # find_or_create_by! 등에서 academic_year 를 명시하면 그 값이 우선한다(||= 는 nil 만 채움).
  def apply_default_academic_year
    self.academic_year ||= self.class.current_academic_year
  end

  def inject_default_rubric_config
    return if rubric_config.present?

    self.rubric_config = {
      "weights" => DEFAULT_RUBRIC_WEIGHTS.stringify_keys,
      "emphasis" => nil,
      "label" => nil
    }
  end
end
