# 상점 카테고리 한국어 라벨(P4.8).
module ShopsHelper
  CATEGORY_LABELS = {
    "food" => "먹이", "evolution_stone" => "진화의 돌", "care" => "케어",
    "decoration" => "장식", "accessory" => "액세서리"
  }.freeze

  def category_label(category)
    CATEGORY_LABELS[category.to_s] || category.to_s
  end
end
