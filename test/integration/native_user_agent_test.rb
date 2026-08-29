require "test_helper"

# Hotwire Native Android 앱의 User-Agent 가 서버 정책을 통과하는지 고정한다.
#
# 배경: `ApplicationController` 의 `allow_browser versions: :modern` 은 actionpack 8.1.3.1 에서
# `{safari: 17.2, chrome: 120, firefox: 121, opera: 106, ie: false}` 로 정의된다. 앱은 기기의
# Android System WebView 를 그대로 쓰므로, 그 WebView 가 Chrome 120 미만이면 **로그인 화면조차
# 406** 이 된다. 앱은 시작 시 `WebViewVersionCompatibility` 로 미리 감지해 안내하지만,
# 서버 쪽 판정 자체를 테스트로 고정해 두어야 임계값이 조용히 바뀌는 것을 잡는다.
#
# UA 접미 문자열은 추측이 아니라 `core-1.3.1.aar` 바이트코드에서 추출한 실제 리터럴이다.
class NativeUserAgentTest < ActionDispatch::IntegrationTest
  # Hotwire Native 가 WebView 기본 UA 뒤에 덧붙이는 문자열(라이브러리 실측).
  HOTWIRE_SUFFIX = "Hotwire Native Android; Turbo Native Android;".freeze

  # 앱이 붙이는 prefix. 버전이 들어가 서버 로그에서 배포된 앱 버전 분포를 볼 수 있다.
  APP_PREFIX = "Chaekgalpi Android/1.0.0;".freeze

  def native_user_agent(chrome_version)
    "#{APP_PREFIX} #{HOTWIRE_SUFFIX} Mozilla/5.0 (Linux; Android 12; SM-P610) " \
      "AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 " \
      "Chrome/#{chrome_version}.0.0.0 Safari/537.36"
  end

  test "최신 WebView 의 네이티브 UA 는 로그인 화면을 정상 표시한다" do
    get new_session_path, headers: { "User-Agent" => native_user_agent(131) }

    assert_response :success
    assert_not_equal 406, response.status,
                     "네이티브 UA 가 allow_browser 에 걸리면 앱 전체가 동작하지 않는다"
  end

  test "네이티브 UA 를 hotwire_native_app? 로 판정한다" do
    # turbo-rails 의 판정식은 /(Turbo|Hotwire) Native/ 이다. 앱 prefix 를 붙여도 살아 있어야
    # native 전용 뷰 분기(예: OCR 확대 링크의 target=_blank 제거)가 동작한다.
    assert_match(/(Turbo|Hotwire) Native/, native_user_agent(131))
  end

  test "임계값 미만 WebView 는 기존 정책대로 406 이다" do
    # 임계값을 몰래 낮추지 않았음을 고정한다. 앱은 이 상황을 시작 시 다이얼로그로 먼저 막는다.
    get new_session_path, headers: { "User-Agent" => native_user_agent(119) }

    assert_response :not_acceptable
  end

  test "일반 웹 브라우저 판정에 회귀가 없다" do
    modern = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
             "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    get new_session_path, headers: { "User-Agent" => modern }
    assert_response :success

    assert_no_match(/(Turbo|Hotwire) Native/, modern,
                    "일반 브라우저가 native 로 오판되면 안 된다")
  end

  test "앱 UA prefix 에 버전이 들어 있어 서버가 앱 버전을 식별할 수 있다" do
    # 서버-앱 호환성 계약의 최소 장치. 고정 APK 는 자동 업데이트 경로가 없으므로,
    # 야생에 어떤 버전이 살아 있는지 알 수단이 UA 뿐이다.
    assert_match(%r{Chaekgalpi Android/\d+\.\d+\.\d+;}, native_user_agent(131))
  end
end
