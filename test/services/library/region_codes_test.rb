require "test_helper"

# 인근 도서관 §5.1 — 교육청명 폐집합 키 → 정보나루 시도 코드. 접미사 제거 없이 정식명 매핑.
class Library::RegionCodesTest < ActiveSupport::TestCase
  # 17개 정식 교육청명 → 정보나루 시도 코드(법정동 아님).
  CANONICAL = {
    "서울특별시교육청" => "11", "부산광역시교육청" => "21", "대구광역시교육청" => "22",
    "인천광역시교육청" => "23", "광주광역시교육청" => "24", "대전광역시교육청" => "25",
    "울산광역시교육청" => "26", "세종특별자치시교육청" => "29", "경기도교육청" => "31",
    "강원특별자치도교육청" => "32", "충청북도교육청" => "33", "충청남도교육청" => "34",
    "전북특별자치도교육청" => "35", "전라남도교육청" => "36", "경상북도교육청" => "37",
    "경상남도교육청" => "38", "제주특별자치도교육청" => "39"
  }.freeze

  test "maps all 17 education offices to their proprietary sido code" do
    assert_equal 17, CANONICAL.size
    CANONICAL.each do |office, code|
      assert_equal code, Library::RegionCodes.for_office(office), "#{office} → #{code}"
    end
  end

  test "accepts special self-governing province aliases" do
    assert_equal "32", Library::RegionCodes.for_office("강원특별자치도교육청")
    assert_equal "32", Library::RegionCodes.for_office("강원도교육청")
    assert_equal "35", Library::RegionCodes.for_office("전북특별자치도교육청")
    assert_equal "35", Library::RegionCodes.for_office("전라북도교육청")
    assert_equal "39", Library::RegionCodes.for_office("제주도교육청")
  end

  test "returns nil for an unknown or blank office" do
    assert_nil Library::RegionCodes.for_office("없는교육청")
    assert_nil Library::RegionCodes.for_office("")
    assert_nil Library::RegionCodes.for_office(nil)
  end

  test "for_school prefers region (education office) over address" do
    school = School.new(region: "부산광역시교육청", address: "서울특별시 노원구 상계로 1")
    assert_equal "21", Library::RegionCodes.for_school(school)
  end

  test "for_school falls back to the address first token when region is blank" do
    school = School.new(region: "", address: "경기도 성남시 분당구 1")
    assert_equal "31", Library::RegionCodes.for_school(school)
  end

  test "for_school returns nil when neither region nor address resolves" do
    assert_nil Library::RegionCodes.for_school(School.new(region: "", address: ""))
    assert_nil Library::RegionCodes.for_school(nil)
  end
end
