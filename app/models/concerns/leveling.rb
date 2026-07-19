# 트레이너(독서가) 레벨·칭호. 누적 경험치 임계 → 1..6 레벨(§13.2).
module Leveling
  extend ActiveSupport::Concern

  # 레벨 임계 경험치(누적). 인덱스 0 == 레벨 1.
  LEVEL_PATH = [ 0, 100, 250, 450, 700, 1000 ].freeze

  # 레벨별 칭호(§13.2).
  TRAINER_TITLES = [
    "책읽기 새내기",
    "책벌레",
    "이야기 탐험가",
    "독서 모험가",
    "책갈피 지킴이",
    "책갈피 마스터"
  ].freeze

  # 현재 트레이너 레벨(1..6).
  def trainer_level
    LEVEL_PATH.rindex { |threshold| experience.to_i >= threshold } + 1
  end

  # 현재 트레이너 칭호.
  def trainer_title
    TRAINER_TITLES[trainer_level - 1]
  end
end
