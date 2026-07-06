require "test_helper"

# P7.4 시스템 설정: 기능 플래그 토글 반영 + API 키류 저장 금지(핵심 보안 가드).
class AdminSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = User.create!(name: "총괄", role: :superadmin, password: "password")
    login_as @superadmin
  end

  test "show renders" do
    get admin_settings_path
    assert_response :success
  end

  test "a feature flag toggle reflects app-wide via AppSetting.feature_enabled?" do
    assert_not AppSetting.feature_enabled?(:beta_mode)
    patch admin_settings_path, params: { feature_flags: '{"beta_mode": true}' }
    assert_redirected_to admin_settings_path
    assert AppSetting.feature_enabled?(:beta_mode)
  end

  test "setting a seasonal banner makes it appear app-wide, and clearing removes it" do
    patch admin_settings_path, params: { seasonal_banner: "여름 독서 축제 진행 중!" }
    get root_path
    assert_match "여름 독서 축제 진행 중!", response.body

    patch admin_settings_path, params: { seasonal_banner: "" }
    get root_path
    assert_no_match "여름 독서 축제 진행 중!", response.body
  end

  test "an API-key-like custom setting is NOT persisted" do
    patch admin_settings_path, params: { setting_key: "gemini_api_key", setting_value: "leaked-secret" }
    assert_nil AppSetting.find_by(key: "gemini_api_key")
    assert_nil AppSetting.get("gemini_api_key")
  end

  test "an API-key-like name nested in feature_flags is scrubbed" do
    patch admin_settings_path, params: { feature_flags: '{"safe_flag": true, "kakao_secret": "x"}' }
    flags = AppSetting.get("feature_flags")
    assert_equal true, flags["safe_flag"]
    assert_not flags.key?("kakao_secret")
  end

  test "AppSetting.set refuses to store sensitive keys at the model level" do
    assert_not AppSetting.set("naver_api_key", "abc")
    assert_not AppSetting.set("something_secret", "abc")
    assert AppSetting.set("safe_setting", "ok")
  end

  test "invalid feature_flags JSON is rejected without crashing" do
    patch admin_settings_path, params: { feature_flags: "{broken" }
    assert_response :unprocessable_entity
  end

  private

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
