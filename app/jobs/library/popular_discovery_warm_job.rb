module Library
  # "이 책은 어때요?" 발견 학년군 인기도서 풀 워밍 잡(무쓰기 카탈로그 매칭).
  # StudentHomeQuery#discovery_books 가 캐시 미스를 만나면 PopularDiscovery 가 스탬피드 가드
  # 마커를 획득한 뒤 이 잡을 큐잉한다. 렌더 경로 밖에서 정보나루 1콜 → 카탈로그 교집합 →
  # 풀 캐시를 채운다(books 테이블 쓰기 0).
  #
  # 계약:
  #   - **멱등**: warm 내부가 이미 풀이 있으면 no-op(재실행·경쟁 안전).
  #   - **무키 no-op**: 서비스 무키면 popular_loans 가 [] → 매칭 임계 미만으로 미캐시.
  #   - 실패는 raise 로 두어 재시도되게 하되, 마커는 WARMING_TTL 자연만료로 재큐잉을 연다.
  class PopularDiscoveryWarmJob < ApplicationJob
    queue_as :default

    def perform(band)
      Library::PopularDiscovery.new.warm(band)
    end
  end
end
