module Schools
  # NEIS 도로명주소(ORG_RDNMA)에서 시군구(기초자치단체)를 추출한다. NEIS `schoolInfo` 에는
  # 깨끗한 시군구 필드가 없어 주소 파싱이 강제되므로(계획 §1.3), 파싱 로직을 dev 전용 rake
  # (`schools:fetch`)에서 분리한 순수 PORO 로 두어 단위 테스트로 정확성을 보장한다.
  #
  # 규칙: 주소의 첫 토큰은 시도(광역), 그 다음 토큰들 중 시/군/구로 끝나는 **첫** 토큰이 기초
  # 자치단체다. 도농복합시(예: "충청남도 천안시 서북구")는 첫 시/군/구 토큰(=시)을 취해 하위
  # 행정구(구)가 아니라 기초자치단체(시)를 반환한다. 세종처럼 단층제라 기초자치단체가 없는
  # 시도는 nil 을 반환한다(피커는 이때 이름검색으로 graceful degrade — gu 는 하드 의존 아님).
  class GuParser
    # 단층제(기초자치단체 없음) 시도 — 예외표(파서 로직과 분리한 데이터). 세종은 도로명주소가
    # "세종특별자치시 <도로명>" 이라 시군구 토큰이 없어 알고리즘상으로도 nil 이지만, 의도를
    # 명시하고 회귀를 막기 위해 데이터로 고정한다.
    SINGLE_TIER_SIDO = %w[세종특별자치시].freeze

    # 기초자치단체 토큰 접미(시/군/구)로 끝나는지 판정.
    GU_SUFFIX = /(시|군|구)\z/
    SIDO_SUFFIX = /(특별시|광역시|특별자치시|도|특별자치도)\z/

    def self.parse(address, region: nil)
      new.parse(address, region: region)
    end

    # address: NEIS 도로명주소. region: 시도교육청명(예외 판정 보조, 선택).
    # 반환: 시군구 문자열 또는 nil(단층제·비정형·빈 주소).
    def parse(address, region: nil)
      tokens = address.to_s.strip.split(/\s+/)
      return nil if tokens.size < 2

      sido = tokens.first
      return nil if single_tier?(sido, region)

      # 일부 NEIS 주소는 시도 토큰 없이 "평택시 …"처럼 시작한다. 광역 시도명이 아니라
      # 기초자치단체 토큰이면 첫 토큰 자체를 시군구로 사용한다.
      return sido if sido.match?(GU_SUFFIX) && !sido.match?(SIDO_SUFFIX)

      # 시도 다음 토큰 중 시/군/구로 끝나는 첫 토큰(도농복합시의 하위 구는 이보다 뒤라 자연히 제외).
      tokens.drop(1).find { |token| token.match?(GU_SUFFIX) }
    end

    private

    def single_tier?(sido, region)
      SINGLE_TIER_SIDO.include?(sido) ||
        SINGLE_TIER_SIDO.any? { |name| region.to_s.include?(name.delete_suffix("특별자치시")) }
    end
  end
end
