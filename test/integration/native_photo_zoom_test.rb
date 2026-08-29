require "test_helper"

# 앱(Hotwire Native)에서 OCR 사진 확대 링크가 살아 있는지 고정한다.
#
# 배경(에뮬레이터 실측, 계획 §N.5): WebView 는 `target="_blank"` 를 무시해 기존 확대 링크가
# **아무 일도 하지 않았다**(화면 그대로, 서버 요청조차 없음). 그렇다고 target 만 빼면 Turbo 가
# 이미지 바이트 응답을 방문으로 처리해 "화면을 불러오지 못했어요" 로 끝난다 — 교사 CSV 에서
# 겪은 실패 모드와 같다. 그래서 앱에서만 이미지를 감싼 HTML 화면으로 보낸다.
#
# **웹 회귀 방지가 이 테스트의 절반이다.** 웹은 지금까지처럼 이미지 바이트를 새 탭으로 열어야 한다.
class NativePhotoZoomTest < ActionDispatch::IntegrationTest
  # `core-1.3.1.aar` 실측 문자열 + 앱 prefix. turbo-rails 판정식은 /(Turbo|Hotwire) Native/ 다.
  NATIVE_UA = "Chaekgalpi Android/1.0.0; Hotwire Native Android; Turbo Native Android; " \
              "Mozilla/5.0 (Linux; Android 12; SM-P610) AppleWebKit/537.36 (KHTML, like Gecko) " \
              "Version/4.0 Chrome/131.0.0.0 Safari/537.36".freeze

  setup do
    @school = School.create!(name: "확대링크학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "확대학생", password: "password")
    @other_student = User.create!(school: @school, classroom: @classroom, name: "남의학생", password: "password")
    @report = ocr_report_with_photo(@student)
  end

  # ── 웹 회귀 ────────────────────────────────────────────────────────────────

  test "웹은 지금까지처럼 이미지 바이트를 새 탭으로 연다" do
    login_as @student

    get report_path(@report)

    assert_response :success
    assert_select "a[href=?][target=?]", report_photo_path(@report, size: :original), "_blank"
    assert_select "a[href=?]", zoom_report_photo_path(@report), count: 0,
                  message: "웹에서 확대 화면으로 보내면 브라우저 확대·저장 동선이 바뀐다"
  end

  # ── 앱 분기 ────────────────────────────────────────────────────────────────

  test "앱은 이미지 바이트가 아니라 HTML 확대 화면으로 보낸다" do
    login_as @student

    get report_path(@report), headers: { "User-Agent" => NATIVE_UA }

    assert_response :success
    assert_select "a[href=?]", zoom_report_photo_path(@report)
    assert_select "a[target=?]", "_blank", count: 0,
                  message: "WebView 가 target=_blank 를 무시해 링크가 죽는다"
  end

  test "앱에서도 확대 링크가 사라지지는 않는다" do
    # 계획 §Phase 7 완료 조건 — "OCR 확대 링크가 사라지지 않음".
    login_as @student

    get report_path(@report), headers: { "User-Agent" => NATIVE_UA }

    assert_select "a[href^=?]", "/reports/#{@report.id}/photo",
                  message: "확대 진입점이 없으면 학생이 자기 사진을 크게 볼 방법이 없다"
  end

  # ── 확대 화면 ──────────────────────────────────────────────────────────────

  test "확대 화면은 바이트를 직접 서빙하지 않고 인증 프록시 URL 을 가리킨다" do
    login_as @student

    get zoom_report_photo_path(@report)

    assert_response :success
    assert_equal "text/html", response.media_type,
                 "이 화면이 바이트를 서빙하면 인가·캐시 정책이 두 곳으로 갈라진다"
    assert_select "img[src=?]", report_photo_path(@report, size: :original)
    assert_select "a[href=?]", report_path(@report)
  end

  test "확대 화면은 상세 페이지와 같은 인가 경계를 쓴다" do
    login_as @other_student

    get zoom_report_photo_path(@report)

    assert_response :forbidden
  end

  test "로그인하지 않으면 확대 화면에 닿지 못한다" do
    get zoom_report_photo_path(@report)

    assert_response :redirect
  end

  test "사진 없는 독후감의 확대 화면은 404 다" do
    without_photo = create_report(@student, input_mode: :ocr)
    login_as @student

    get zoom_report_photo_path(without_photo)

    assert_response :not_found
  end

  private

  def create_report(user, attrs = {})
    Report.create!({ user: user, classroom: @classroom, book_title: "책", body: "본문",
                     ai_status: :done }.merge(attrs))
  end

  def ocr_report_with_photo(user)
    create_report(user, input_mode: :ocr).tap do |report|
      report.photo.attach(io: StringIO.new(png_bytes), filename: "handwriting.png", content_type: "image/png")
    end
  end

  def png_bytes
    [ 137, 80, 78, 71, 13, 10, 26, 10 ].pack("C*") + ("\x00" * 64)
  end
end
