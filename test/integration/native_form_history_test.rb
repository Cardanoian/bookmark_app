require "test_helper"

# 앱에서 독후감 제출 뒤 뒤로가기가 **입력값이 남은 작성 폼**으로 돌아가 같은 글을 한 편 더 만들 수
# 있었다(에뮬레이터 실측: 독후감 2편이 실제로 생성됨). 새 글 폼만 `data-turbo-action="replace"` 로
# 작성 폼을 히스토리에서 걷어내 그 경로를 막는다.
#
# **웹은 이 분기 밖이다.** 웹 히스토리 동작이 바뀌지 않는 것을 함께 고정한다.
class NativeFormHistoryTest < ActionDispatch::IntegrationTest
  NATIVE_UA = "Chaekgalpi Android/1.0.0; Hotwire Native Android; Turbo Native Android; " \
              "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) " \
              "Version/4.0 Chrome/131.0.0.0 Safari/537.36".freeze

  setup do
    @school = School.create!(name: "폼히스토리학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "폼학생", password: "password")
    login_as @student
  end

  test "앱의 새 독후감 폼은 제출 방문을 replace 로 바꾼다" do
    get new_report_path(input_mode: :keyboard), headers: { "User-Agent" => NATIVE_UA }

    assert_response :success
    assert_select "form[action=?][data-turbo-action=?]", reports_path, "replace",
                  message: "작성 폼이 히스토리에 남으면 뒤로가기 후 재제출로 같은 독후감이 두 편 생긴다"
  end

  test "웹의 새 독후감 폼은 히스토리 동작이 바뀌지 않는다" do
    get new_report_path(input_mode: :keyboard)

    assert_response :success
    assert_select "form[action=?]", reports_path
    assert_select "form[data-turbo-action]", count: 0,
                  message: "웹 히스토리 동작은 이번 변경 범위 밖이다"
  end

  test "고쳐쓰기 폼은 앱에서도 replace 하지 않는다" do
    # update 는 같은 글을 다시 저장할 뿐이라 중복 생성이 없고, 뒤로 돌아가 이어서 고치는 것은 정상 동선이다.
    report = Report.create!(user: @student, classroom: @classroom, book_title: "책", body: "본문",
                            ai_status: :done, input_mode: :keyboard)

    get edit_report_path(report), headers: { "User-Agent" => NATIVE_UA }

    assert_response :success
    assert_select "form[data-turbo-action]", count: 0
  end
end
