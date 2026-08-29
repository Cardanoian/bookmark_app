module Library
  # 인근 도서관 워밍 잡. `NearbyAvailability#call`(렌더 경로)이 캐시 미스를 만나면 스탬피드
  # 가드 마커를 획득한 뒤 이 잡을 큐잉하고 `:warming` 으로 즉시 돌아온다. 실제 정보나루 호출은
  # 여기서, 요청 밖에서 한다.
  #
  # 왜 굳이 잡으로 빼냐 — 운영 실측(2026-08-29)에서 `libSrchByBook` 이 9.2~9.8초,
  # `bookExist` 1콜이 7.9~35.5초였다. 5곳이면 순차 101초·동시 8.7초라 콜드 한 번에 최소
  # 18초가 든다. 이걸 렌더 안에서 감당할 방법은 없다(시간예산을 조이면 "확인 필요"만 늘고,
  # 늘리면 아이가 그만큼 기다린다).
  #
  # 계약:
  #   - **멱등**: `warm!` 이 캐시 히트면 외부 콜 없이 같은 결과를 낸다(재실행·경쟁 안전).
  #   - **무키 no-op**: 서비스 무키면 `:no_key` 로 즉시 끝나고 방송도 그 상태를 싣는다.
  #   - 방송 실패가 이미 채워진 캐시를 되돌리지 않는다(별도 rescue — AiReviewJob 선례).
  class NearbyLibrariesWarmJob < ApplicationJob
    queue_as :default

    def perform(book_id, school_id)
      book = Book.find_by(id: book_id)
      school = School.find_by(id: school_id)
      return unless book && school

      nearby = Library::NearbyAvailability.new(book: book, school: school).warm!

      begin
        broadcast(book, school, nearby)
      rescue StandardError => e
        Rails.logger.error("NearbyLibrariesWarmJob broadcast failed for book #{book_id}/school #{school_id}: #{e.class}: #{e.message}")
      end
    end

    private

    # 워밍이 끝난 프레임을 완성본으로 교체한다. target 은 파셜이 감싸는 turbo_frame_tag 와 같은
    # id 라, 교체 결과도 동일 id 프레임이 된다(lazy src 프레임의 "content missing" 방지 규약 유지).
    def broadcast(book, school, nearby)
      Turbo::StreamsChannel.broadcast_replace_to(
        [ school.id, book.id, :nearby_libraries ],
        target: "nearby_libraries",
        partial: "reading_activities/nearby_libraries",
        locals: { nearby: nearby }
      )
    end
  end
end
