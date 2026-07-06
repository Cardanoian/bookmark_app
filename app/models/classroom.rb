class Classroom < ApplicationRecord
  DEFAULT_RUBRIC_WEIGHTS = { content: 1, emotion: 1, life: 1, structure: 1, spelling: 1 }.freeze

  belongs_to :school
  belongs_to :teacher, class_name: "User", optional: true
  has_many :users, dependent: :nullify
  has_many :reports, dependent: :destroy

  validates :class_no, uniqueness: { scope: [ :school_id, :grade ] }

  before_validation :inject_default_rubric_config, on: :create

  def label
    "#{grade}학년 #{class_no}반"
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

  def inject_default_rubric_config
    return if rubric_config.present?

    self.rubric_config = {
      "weights" => DEFAULT_RUBRIC_WEIGHTS.stringify_keys,
      "emphasis" => nil,
      "label" => nil
    }
  end
end
