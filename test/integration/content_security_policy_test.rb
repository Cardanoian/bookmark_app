require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "a normal page response carries an enforced Content-Security-Policy header" do
    get new_session_path
    assert_response :success

    csp = response.headers["Content-Security-Policy"]
    assert csp.present?, "CSP 헤더가 있어야 한다"
    assert_includes csp, "default-src 'self'"
    assert_includes csp, "script-src 'self'"
    assert_includes csp, "object-src 'none'"
    # 외부 도서 표지(https)와 업로드 미리보기(blob:)가 차단되지 않아야 한다(브라우저 파손 방지).
    assert_includes csp, "img-src 'self' data: blob: https:"
  end

  test "the layout exposes a per-request script nonce for importmap" do
    get new_session_path
    assert_select "meta[name=csp-nonce]"
  end
end
