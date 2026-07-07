require "test_helper"

# 2.9 인가 안전망(fail-closed). authorize 를 호출하지 않은 액션이 조용히 열리는 fail-open 을
# 막기 위해 ApplicationController 에 after_action :verify_authorized 가 항상 걸려 있어야 한다.
# 이 콜백이 제거되면 향후 authorize 누락 액션이 무방비로 열리므로, 그 회귀를 여기서 잡는다.
class AuthorizationSafetyNetTest < ActiveSupport::TestCase
  test "ApplicationController runs verify_authorized as a fail-closed after_action" do
    registered = ApplicationController._process_action_callbacks.any? do |callback|
      callback.kind == :after && callback.filter == :verify_authorized
    end

    assert registered, "authorize 누락 액션을 fail-closed 로 잡으려면 verify_authorized 안전망이 있어야 한다"
  end
end
