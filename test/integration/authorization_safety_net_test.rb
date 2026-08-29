require "test_helper"

# 2.9 인가 안전망(fail-closed). authorize 를 호출하지 않은 액션이 조용히 열리는 fail-open 을
# 막기 위해 ApplicationController 에 after_action :verify_authorized 가 항상 걸려 있어야 한다.
# 이 콜백이 제거되면 향후 authorize 누락 액션이 무방비로 열리므로, 그 회귀를 여기서 잡는다.
class AuthorizationSafetyNetTest < ActiveSupport::TestCase
  # `ApplicationController` 를 상속하지 **않아도 되는** 컨트롤러. 여기 오르는 순간 그 컨트롤러는
  # 로그인·인가·정지확인·브라우저 게이트를 **하나도 통과하지 않는다.** 추가는 의식적 결정이어야 하며
  # 아래 개별 계약 테스트로 그 대가를 함께 못박는다.
  ALLOWED_OUTSIDE_APPLICATION_CONTROLLER = %w[
    NativeConfigurationsController
  ].freeze

  test "ApplicationController runs verify_authorized as a fail-closed after_action" do
    registered = ApplicationController._process_action_callbacks.any? do |callback|
      callback.kind == :after && callback.filter == :verify_authorized
    end

    assert registered, "authorize 누락 액션을 fail-closed 로 잡으려면 verify_authorized 안전망이 있어야 한다"
  end

  # 위 테스트는 **ApplicationController 안에 사는 컨트롤러만** 지킨다. 상속을 끊은 컨트롤러는
  # 안전망 바깥이라 아무 검사도 받지 않는데, 그런 컨트롤러가 새로 생겨도 **화면도 테스트도
  # 아무 말을 하지 않는다.** 그래서 파일 목록에서 직접 훑어 허용목록과 대조한다.
  test "app/controllers 의 모든 컨트롤러는 ApplicationController 를 상속하거나 허용목록에 있어야 한다" do
    root = Rails.root.join("app/controllers")
    controllers = Dir[root.join("**/*_controller.rb")].map do |path|
      Pathname.new(path).relative_path_from(root).to_s.delete_suffix(".rb").camelize.constantize
    end
    assert_operator controllers.size, :>, 50, "컨트롤러 수집이 실패하면 이 테스트가 조용히 무력해진다"

    outside = controllers.reject { |klass| klass <= ApplicationController }.map(&:name).sort

    assert_equal ALLOWED_OUTSIDE_APPLICATION_CONTROLLER, outside,
                 "ApplicationController 를 상속하지 않는 컨트롤러가 새로 생겼다. " \
                 "그 컨트롤러는 로그인·인가·정지확인을 하나도 거치지 않는다 — " \
                 "의도한 것이면 ALLOWED_OUTSIDE_APPLICATION_CONTROLLER 에 올리고 계약 테스트를 함께 추가할 것."
  end

  # 허용목록에 올린 대가를 명시한다. 인가 체인 밖에 두는 근거는 "쿠키·CSRF·flash·뷰가 애초에
  # 없어서 사용자 컨텍스트를 다루는 표면이 좁다"는 것이다. `ActionController::Base` 로 바뀌면
  # 그 근거가 통째로 사라지므로 여기서 깨진다.
  #
  # ⚠️ **`session` 은 예외다.** `ActionController::Metal` 이 `@_request.session` 으로 위임하고
  #   세션 미들웨어는 앱 전역에 있어서, API 컨트롤러에서도 `session` 은 **읽힌다.** 그래서 이건
  #   구조로 막지 못하고 아래 소스 검사로 막는다(초기 주석이 "구조적으로 불가능"이라고 단언했는데
  #   사실이 아니었다 — Phase 9 감사에서 정정).
  test "허용목록 컨트롤러는 쿠키·CSRF·flash·뷰가 없는 ActionController::API 여야 한다" do
    klass = NativeConfigurationsController
    assert_operator klass, :<, ActionController::API,
                    "인가 체인 밖 컨트롤러는 API 컨트롤러여야 한다"
    assert_not klass.method_defined?(:cookies), "인가 체인 밖 컨트롤러가 쿠키를 읽으면 안 된다"

    [ ActionController::Cookies, ActionController::RequestForgeryProtection,
      ActionController::Flash, ActionView::Layouts ].each do |mod|
      assert_not_includes klass.ancestors, mod, "#{mod} 가 붙으면 API 컨트롤러로 둔 근거가 사라진다"
    end
  end

  test "허용목록 컨트롤러 소스가 사용자 컨텍스트를 건드리지 않는다" do
    # session 은 API 컨트롤러에서도 읽히므로(위 참조) 구조가 아니라 소스로 막는다.
    source = Rails.root.join("app/controllers/native_configurations_controller.rb").read
    code = source.lines.grep_v(/^\s*#/).join # 주석은 제외(설명에 단어가 등장한다)

    %w[session cookies Current current_user authorize policy_scope].each do |token|
      assert_no_match(/\b#{token}\b/, code,
                      "인가 체인 밖 컨트롤러가 `#{token}` 을 건드리면 익명·캐시 가능 계약이 깨진다")
    end
  end
end
