module SchoolsHelper
  # "서울특별시교육청" → "서울특별시" (아동 친화 표시). 캐스케이딩 1단계 시도 라벨.
  # region 컬럼 값(교육청명)은 그대로 두고 표시만 정규화한다.
  def school_region_label(region)
    region.to_s.sub(/교육청\z/, "")
  end
end
