# Hotwire Native 앱이 받아가는 원격 Path Configuration.
#
# **`ApplicationController` 를 상속하지 않는다.** 상속하면 다음이 전부 걸린다.
#   allow_browser :modern / require_login / verify_authorized(fail-closed) /
#   set_current_user / enforce_not_suspended / require_student_ranking_profile / MonsterDiscovery
# 이 응답은 로그인·인가·사용자 컨텍스트가 필요 없는 **공개 정적 JSON** 이고, 요청 주체도 WebView 가
# 아니라 Hotwire Native 의 자체 HTTP 클라이언트다. 필터를 개별 `skip_*` 로 뚫는 것은 취약하다 —
# 특히 `allow_browser` 는 익명 람다 `before_action` 이라 Rails 가 skip API 를 제공하지 않는다.
# 상속을 끊는 편이 향후 `ApplicationController` 에 필터가 추가돼도 조용히 깨지지 않는다.
#
# `ActionController::API` 를 쓰는 이유: ETag(`ConditionalGet`)·캐싱·렌더러는 그대로 얻으면서
# 쿠키·세션·flash·CSRF·레이아웃·뷰 렌더링은 애초에 없다. 익명·캐시 가능해야 할 엔드포인트에서
# 누군가 나중에 `session` 을 읽는 사고가 구조적으로 불가능해진다.
#
# public/ 정적 파일로 두지 않는 이유: production 은 정적 파일에 최대 1년 cache-control 을 적용해
# 원격 설정의 "APK 재배포 없이 즉시 조정" 목적이 사라진다. 여기서 짧은 max-age 와 ETag 를 준다.
#
# 스로틀은 걸지 않는다(의식적 결정) — 응답이 메모리에 캐시된 상수 문자열이고 Cloudflare 가 앞에 있다.
class NativeConfigurationsController < ActionController::API
  # 앱이 의존하는 계약이므로 파일이 없으면 조용히 빈 응답을 주지 않고 즉시 실패시킨다.
  CONFIG_PATH = Rails.root.join("config", "hotwire_native", "android_v1.json").freeze

  def show
    json = self.class.android_v1_json

    # 앱은 이 파일을 자주 재요청한다. ETag 로 304 를 유도하되, max-age 는 짧게 두어
    # 규칙을 고쳤을 때 하루 안에 반영되게 한다(정적 파일의 1년 캐시와 대비).
    expires_in 5.minutes, public: true
    render json: json
  end

  # 파일을 매 요청 읽지 않고 부팅 시 한 번 읽어 캐시한다. 내용이 사용자와 무관한 상수이기 때문이다.
  # development 에서는 편집 즉시 반영되도록 캐시하지 않는다.
  def self.android_v1_json
    if Rails.env.development?
      read_config
    else
      @android_v1_json ||= read_config
    end
  end

  def self.read_config
    raise "Hotwire Native path configuration 이 없습니다: #{CONFIG_PATH}" unless CONFIG_PATH.exist?

    CONFIG_PATH.read
  end
  private_class_method :read_config
end
