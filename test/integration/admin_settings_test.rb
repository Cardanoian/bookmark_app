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
    # 배너는 application 레이아웃(shared/_seasonal_banner)에서 렌더된다. 총괄관리자는 root 에서
    # /admin 콘솔로 리다이렉트되어 이 레이아웃을 타지 않으므로, "전역 노출"은 학생 대시보드로 확인한다.
    school = School.create!(name: "배너초등학교")
    classroom = Classroom.create!(school: school, grade: 3, class_no: 1)
    student = User.create!(school: school, classroom: classroom, name: "배너학생", password: "password")

    patch admin_settings_path, params: { seasonal_banner: "여름 독서 축제 진행 중!" }

    reset!
    login_as student
    get root_path
    assert_match "여름 독서 축제 진행 중!", response.body

    reset!
    login_as @superadmin
    patch admin_settings_path, params: { seasonal_banner: "" }

    reset!
    login_as student
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
end
