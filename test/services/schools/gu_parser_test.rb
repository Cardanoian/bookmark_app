require "test_helper"

# 시군구 파서 단위 테스트(계획 §1.3, Critic Major 1). NEIS 도로명주소에서 기초자치단체를
# 정확히 뽑는지, 도농복합시·세종 단층제·비정형 주소 등 경계를 커버한다.
class Schools::GuParserTest < ActiveSupport::TestCase
  test "특별시 자치구를 추출한다" do
    assert_equal "강남구", Schools::GuParser.parse("서울특별시 강남구 언주로 3")
  end

  test "광역시 자치구를 추출한다" do
    assert_equal "해운대구", Schools::GuParser.parse("부산광역시 해운대구 우동 1409")
  end

  test "도의 시(대도시)는 하위 행정구가 아니라 시를 반환한다" do
    assert_equal "수원시", Schools::GuParser.parse("경기도 수원시 팔달구 효원로 1")
  end

  test "도농복합시(시+구)도 하위 구가 아니라 시를 반환한다" do
    assert_equal "천안시", Schools::GuParser.parse("충청남도 천안시 서북구 번영로 156")
  end

  test "도농복합시의 읍/면 주소도 시를 반환한다" do
    assert_equal "포천시", Schools::GuParser.parse("경기도 포천시 소흘읍 죽엽산로 111")
  end

  test "도의 군을 추출한다" do
    assert_equal "청도군", Schools::GuParser.parse("경상북도 청도군 화양읍 범곡길 1")
  end

  test "시도 토큰이 생략된 주소는 첫 시군구 토큰을 사용한다" do
    assert_equal "평택시", Schools::GuParser.parse("평택시 고덕국제5로 165", region: "경기도교육청")
  end

  test "특별자치도의 시를 추출한다" do
    assert_equal "춘천시", Schools::GuParser.parse("강원특별자치도 춘천시 백령로 100")
    assert_equal "제주시", Schools::GuParser.parse("제주특별자치도 제주시 문연로 6")
  end

  test "세종(단층제)은 시군구가 없어 nil 을 반환한다" do
    assert_nil Schools::GuParser.parse("세종특별자치시 한누리대로 2154")
  end

  test "region(교육청)만으로도 세종을 단층제로 판정해 nil 을 반환한다" do
    # 방어적: 주소가 비정형이어도 region 이 세종이면 nil.
    assert_nil Schools::GuParser.parse("세종특별자치시 조치원읍 군청로 87", region: "세종특별자치시교육청")
  end

  test "예외표(SINGLE_TIER_SIDO)의 각 엔트리는 단층제로 처리된다" do
    Schools::GuParser::SINGLE_TIER_SIDO.each do |sido|
      assert_nil Schools::GuParser.parse("#{sido} 어떤로 1"),
                 "#{sido} 은 단층제라 gu 가 nil 이어야 한다"
    end
  end

  test "빈/비정형/nil 주소는 nil 을 반환한다(graceful)" do
    assert_nil Schools::GuParser.parse("")
    assert_nil Schools::GuParser.parse(nil)
    assert_nil Schools::GuParser.parse("서울특별시") # 시도 토큰만
    assert_nil Schools::GuParser.parse("주소미상")
  end
end
