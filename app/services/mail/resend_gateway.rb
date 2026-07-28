# Resend 발송 설정의 단일 진실(키·발신주소·가용성·실패 분류).
#
# 키 소스는 리포 규약을 그대로 따른다 — **ENV 우선, 없으면 credentials 폴백**
# (`docs/API_KEYS.md` §1.1, 선례: `Ai::ClaudeClient` · `Books::SearchService`).
# 판정 술어 `available?` 도 같은 선례를 미러한다(`Ai::ClaudeClient.available?`).
#
# `available?` 는 단순한 키 존재 판정을 넘어 **이메일 인증 게이트의 마스터 스위치**다
# (`User#email_verification_gate_active?`). 키가 없는 개발·CI·오프라인 시연에서는 게이트가
# 통째로 꺼져 기존 흐름이 100% 보존되고, 운영 중 메일 장애가 길어지면 운영자가 키를 비워
# 게이트를 즉시 전면 해제할 수 있다(비상 킬 스위치 — `docs/API_KEYS.md` 참조).
#
# 실패 분류(`classify`)는 **관측용이지 제어용이 아니다**. resend 젬은 403 을 예외 클래스에
# 매핑하지 않고(`ERRORS` 테이블에 400/401/404/422/429/500 만 존재) `Resend::Error` 기본
# 클래스로 올리며, HTTP status 접근자(`code`)도 공개하지 않는다(`attr_reader :headers` 뿐).
# 그래서 도메인 미검증을 가려내려면 메시지 문자열 매칭 외에 방법이 없는데, 이 매칭은 젬
# 업데이트로 깨질 수 있다. 따라서 분류가 틀려도 **사용자 응답·폴백 경로는 동일**하게 두고,
# 분류는 감사 로그의 action 라벨만 바꾸도록 폭발 반경을 제한했다. 원문 메시지는 항상
# metadata 에 함께 저장하므로 문구가 바뀌어도 로그에서 즉시 확인된다.
module Mail
  module ResendGateway
    # 도메인 미검증 403 응답의 메시지 조각("The domain is not verified.").
    # ⚠️ resend 젬 업데이트 시 문구 변경 가능 — 감사 로그에 미분류 실패가 몰리면 여기부터 확인한다.
    UNVERIFIED_DOMAIN_HINT = "not verified"

    # 검증 완료된 발신 도메인(gbeai.net)의 주소. 앱 서비스 호스트(book.gbeai.net)와 다른 것은
    # 정상이다 — Resend 도메인 검증은 발신 도메인 기준이고, 메일 링크 호스트와 무관하다.
    DEFAULT_FROM = "책갈피 <admin@gbeai.net>"

    module_function

    def api_key
      ENV["RESEND_API_KEY"].presence || Rails.application.credentials.dig(:resend, :api_key)
    end

    def available?
      api_key.present?
    end

    def from_address
      ENV["MAIL_FROM"].presence || DEFAULT_FROM
    end

    # 발송 실패 원인 분류 → :domain_unverified | :quota | :unknown (감사 로그 라벨용).
    def classify(error)
      return :quota if error.is_a?(Resend::Error::RateLimitExceededError)
      return :domain_unverified if error.message.to_s.include?(UNVERIFIED_DOMAIN_HINT)

      :unknown
    end
  end
end
