require "test_helper"

# Hotwire Native Android 앱이 시작할 때 받아가는 원격 Path Configuration 의 계약 테스트.
#
# 이 응답이 깨지면 배포된 APK 전체가 영향을 받는데, 앱은 재배포 없이 고칠 수 없다.
# 그래서 "JSON 이 나온다" 수준이 아니라 **앱이 실제로 의존하는 계약**을 고정한다.
class NativeConfigurationTest < ActionDispatch::IntegrationTest
  ANDROID_ASSET_COPY = Rails.root.join(
    "android", "app", "src", "main", "assets", "json", "path_configuration.json"
  )

  test "비로그인 상태에서 200 을 준다" do
    # 앱은 로그인 전에 이 파일을 받는다. require_login 리다이렉트에 걸리면 안 된다.
    get android_v1_configuration_path
    assert_response :success
  end

  test "JSON 으로 파싱되고 settings·rules 키를 가진다" do
    get android_v1_configuration_path

    body = JSON.parse(response.body)
    assert body.key?("settings"), "settings 키가 있어야 한다"
    assert body.key?("rules"), "rules 키가 있어야 한다"
  end

  test "application/json 으로 응답한다" do
    get android_v1_configuration_path
    assert_equal "application/json", response.media_type
  end

  test "첫 규칙이 모든 경로를 받는 기본 규칙이고 uri 를 가진다" do
    # Hotwire 는 첫 규칙을 기본값으로 삼고 뒤 규칙이 이를 상속한다.
    # 첫 규칙에 uri 가 없으면 앱이 목적지 Fragment 를 찾지 못한다.
    get android_v1_configuration_path
    rules = JSON.parse(response.body).fetch("rules")

    assert rules.any?, "규칙이 하나 이상 있어야 한다"
    first = rules.first
    assert_includes first.fetch("patterns"), ".*", "첫 규칙은 모든 경로를 받아야 한다"
    assert_equal "hotwire://fragment/web", first.dig("properties", "uri")
  end

  test "v1 은 pull-to-refresh 를 끈다" do
    # 장문 독후감 작성 중 당겨서 새로고침이 입력을 날리는 사고를 막는다(계획 §4.3).
    get android_v1_configuration_path
    first = JSON.parse(response.body).fetch("rules").first

    assert_equal false, first.dig("properties", "pull_to_refresh_enabled")
  end

  test "세션·사용자 데이터를 포함하지 않는다" do
    get android_v1_configuration_path

    # 문자열 "session" 자체는 정상이다 — `^/session/new$` 는 앱이 로그인 화면을 인식하는
    # **경로 패턴**이다. 검사해야 할 것은 응답이 요청자에 따라 달라지는 값을 싣는지다.
    body = JSON.parse(response.body)
    assert_equal %w[rules settings], body.keys.sort,
                 "최상위 키는 settings·rules 뿐이어야 한다"

    # 규칙은 경로 패턴과 화면 속성만 담는다. 자격증명·개인정보성 키가 끼어들면 실패시킨다.
    leaky = %w[user_id email password token secret api_key school student current_user]
    flat = response.body.downcase
    leaky.each do |key|
      assert_not_includes flat, key, "원격 설정에 '#{key}' 가 들어가면 안 된다"
    end

    # 익명·캐시 가능한 응답이어야 한다. 쿠키를 심으면 CDN 캐시에 세션이 섞인다.
    assert_nil response.headers["Set-Cookie"]
  end

  test "로그인 상태와 무관하게 동일한 응답을 준다" do
    # 요청자에 따라 내용이 달라지면 공유 캐시에 사용자별 응답이 섞인다.
    get android_v1_configuration_path
    anonymous = response.body

    school = School.create!(name: "설정테스트학교")
    classroom = Classroom.create!(school: school, grade: 3, class_no: 1)
    student = User.create!(
      school: school, classroom: classroom, name: "설정테스트학생", password: "password"
    )
    login_as student

    get android_v1_configuration_path
    assert_response :success
    assert_equal anonymous, response.body
  end

  test "짧은 캐시와 ETag 를 준다" do
    # 정적 파일의 1년 캐시를 피해 컨트롤러로 서빙하는 목적이 여기 있다.
    get android_v1_configuration_path

    assert response.headers["ETag"].present?, "ETag 가 있어야 조건부 요청이 된다"
    cache_control = response.headers["Cache-Control"]
    assert_match(/public/, cache_control)
    assert_match(/max-age=(\d+)/, cache_control)
    assert_operator cache_control[/max-age=(\d+)/, 1].to_i, :<=, 1.hour.to_i,
                    "원격 설정은 짧은 max-age 여야 즉시 조정 목적이 살아난다"
  end

  test "ETag 가 일치하면 304 를 준다" do
    get android_v1_configuration_path
    etag = response.headers["ETag"]

    get android_v1_configuration_path, headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  # ── 번들 사본과의 계약 ────────────────────────────────────────────────────────
  # 두 사본이 **항상 같아야 한다고 단언하지 않는다.** 원격 사본의 존재 이유가
  # "APK 재배포 없이 규칙을 바꾸는 것"이라, 엄격한 동일성 테스트는 그 유일한 정당한
  # 유스케이스를 스스로 금지한다. 대신 호환성이 깨지는 변화만 잡는다.

  test "번들 사본이 원격 없이도 자립 가능한 폴백이다" do
    assert ANDROID_ASSET_COPY.exist?, "APK 번들 사본이 있어야 원격 장애 때 앱이 뜬다"

    bundled = JSON.parse(ANDROID_ASSET_COPY.read)
    first = bundled.fetch("rules").first

    assert_includes first.fetch("patterns"), ".*"
    assert_equal "hotwire://fragment/web", first.dig("properties", "uri"),
                 "번들 사본만으로도 목적지를 찾을 수 있어야 한다"
  end

  # ── 다운로드 규칙 ────────────────────────────────────────────────────────────
  # 앱은 이 표시를 보고 "화면 이동" 대신 "파일 저장"으로 분기한다. 표시가 빠지면 Turbo 가 내려받기
  # 링크를 방문으로 처리해 앱에는 오류 화면만 뜨고 **서버에는 다운로드 감사 로그가 남는다** —
  # 아무도 받지 못한 파일이 내려받아진 것으로 기록된다. 그래서 규칙 존재 여부를 테스트로 고정한다.

  DOWNLOAD_PATHS = {
    "/teacher/exports/reports_xlsx" => "교사 5축 사전·사후 엑셀",
    "/admin/analytics/export" => "총괄 전국 통계 CSV",
    "/agree.pdf" => "보호자 동의서 PDF"
  }.freeze

  test "다운로드 대상 경로가 download 규칙에 매칭된다" do
    get android_v1_configuration_path
    rules = JSON.parse(response.body).fetch("rules")

    DOWNLOAD_PATHS.each do |path, label|
      matched = rules.any? do |rule|
        rule.dig("properties", "download") == true &&
          rule.fetch("patterns").any? { |pattern| Regexp.new(pattern).match?(path) }
      end

      assert matched, "#{label}(#{path})이 download 규칙에 걸리지 않는다"
    end
  end

  test "다운로드 경로가 실제 라우트와 일치한다" do
    # 위 테스트는 문자열 경로를 검사한다. 라우트가 바뀌면 그 문자열도 함께 낡으므로,
    # 헬퍼가 만드는 실제 경로와 대조해 둘이 같이 늙지 않게 한다.
    assert_equal "/teacher/exports/reports_xlsx", teacher_exports_reports_xlsx_path
    assert_equal "/admin/analytics/export", admin_analytics_export_path
    assert Rails.public_path.join("agree.pdf").exist?, "동의서 PDF 가 public/ 에 있어야 한다"
  end

  test "일반 화면 경로는 download 규칙에 걸리지 않는다" do
    # `\.pdf$` 같은 패턴이 과하게 넓어지면 평범한 화면이 저장 대화상자로 새어 나간다.
    get android_v1_configuration_path
    rules = JSON.parse(response.body).fetch("rules")
    download_rules = rules.select { |rule| rule.dig("properties", "download") == true }

    %w[/ /session/new /reports /reports/1 /teacher /monsters /admin/analytics].each do |path|
      leaked = download_rules.any? do |rule|
        rule.fetch("patterns").any? { |pattern| Regexp.new(pattern).match?(path) }
      end

      assert_not leaked, "화면 경로 #{path} 가 다운로드로 처리되면 안 된다"
    end
  end

  test "download 규칙은 확장자와 파일명을 함께 준다" do
    # 라우팅으로 잡은 다운로드는 응답 헤더가 없어 URL 마지막 조각밖에 단서가 없다.
    # 확장자 없는 이름으로 저장되면 기기에서 열리지 않으므로 MIME 을 함께 내려 준다.
    get android_v1_configuration_path
    rules = JSON.parse(response.body).fetch("rules")

    rules.select { |rule| rule.dig("properties", "download") == true }.each do |rule|
      assert rule.dig("properties", "download_mime").present?,
             "download 규칙 #{rule['patterns'].inspect} 에 download_mime 이 없다"
    end
  end

  test "번들 사본과 서버 사본의 schema_version 이 같다" do
    # 규칙 내용의 의도적 divergence 는 허용하되, 스키마가 갈리면 구 APK 가 새 규칙을
    # 해석하지 못하므로 그것만 실패시킨다.
    get android_v1_configuration_path
    remote = JSON.parse(response.body)
    bundled = JSON.parse(ANDROID_ASSET_COPY.read)

    assert_equal bundled.dig("settings", "schema_version"),
                 remote.dig("settings", "schema_version"),
                 "schema_version 이 갈리면 배포된 APK 가 원격 규칙을 해석하지 못한다"
  end
end
