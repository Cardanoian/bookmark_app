require "test_helper"

# 라이브 갱신 구독(`turbo_stream_from`)이 각 화면에 살아 있는지 고정한다.
#
# 이 구독이 사라지면 **화면은 멀쩡히 뜨고 아무 오류도 나지 않는다.** 다만 첨삭이 끝나도, 선생님이
# 승인해도, 몬스터가 진화해도 화면이 그대로 멈춰 있을 뿐이다. 테스트로 묶어 두지 않으면
# 파셜을 정리하다 조용히 지워질 수 있는 종류의 마크업이다.
#
# Android 앱(WebView)에서 각 화면의 `turbo-cable-stream-source` 가 실제로 connected 되는 것을
# 에뮬레이터로 확인했고(계획 §N.8), 여기서는 서버가 그 마크업을 계속 내보내는지만 지킨다.
class LiveUpdateSubscriptionsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "라이브학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "라이브담임",
                            role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "라이브학생", password: "password")
  end

  test "독후감 수정 화면이 OCR 본문 채움 방송을 구독한다" do
    # OcrJob 이 사진을 다 읽으면 이 채널로 본문 textarea 를 채운다. 구독이 없으면 학생은
    # "읽고 있어요" 화면에서 영영 기다린다.
    report = draft_report
    login_as @student

    get edit_report_path(report)

    assert_response :success
    assert_select "turbo-cable-stream-source", 1
  end

  test "몬스터 도감이 활성 몬스터 변경을 구독한다" do
    login_as @student

    get monsters_path

    assert_response :success
    assert_select "turbo-cable-stream-source", 1
  end

  test "몬스터 상세가 활성 몬스터 변경을 구독한다" do
    species = MonsterSpecies.first
    skip "몬스터 시드가 없는 테스트 DB" if species.nil?
    login_as @student

    get monster_path(species)

    assert_response :success
    assert_select "turbo-cable-stream-source", 1
  end

  test "랭킹 화면이 학급 랭킹 갱신을 구독한다" do
    login_as @student

    get rankings_path

    assert_response :success
    assert_select "turbo-cable-stream-source", 1
  end

  test "교사 검토 큐가 신규 제출 append 를 구독한다" do
    # 미검토 탭에서만 구독한다 — 검토완료 탭·2페이지에 걸면 append 행이 엉뚱한 목록에 붙는다.
    login_as @teacher

    get teacher_reviews_path

    assert_response :success
    assert_select "turbo-cable-stream-source", 1
  end

  test "교사 검토 큐의 검토완료 탭은 구독하지 않는다" do
    login_as @teacher

    get teacher_reviews_path(status: "reviewed")

    assert_response :success
    assert_select "turbo-cable-stream-source", count: 0,
                  message: "검토완료 목록에 미검토 신규 행이 append 되면 안 된다"
  end

  private

  def draft_report
    Report.create!(user: @student, classroom: @classroom, book_title: "책",
                   body: "본문", ai_status: :done, input_mode: :ocr)
  end
end
