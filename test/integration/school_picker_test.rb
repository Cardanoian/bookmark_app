require "test_helper"

# 학교 선택 목록형 드롭다운(WS-E). 회원가입(with_classroom:false)·학생 로그인(with_classroom:true)
# 두 렌더처가 hidden school_id + 클릭 가능한 결과 목록 구조를 갖는지, 그리고 JS 가 의존하는
# 백엔드 계약(검색→결과, 선택 학교 학급 캐스케이딩)과 최종 제출(school_id 세팅→로그인)이
# 이어지는지 확인한다. 실제 <li> 클릭은 JS 라 rack 테스트로는 계약 단위로 검증한다.
class SchoolPickerTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "목록피커초등학교", region: "서울특별시교육청", gu: "강남구")
    @classroom = Classroom.create!(school: @school, grade: 4, class_no: 1)
    @student = User.create!(
      school: @school, classroom: @classroom, name: "피커학생", password: "password"
    )
  end

  # ── 회원가입 폼(학급 select 없음) ──────────────────────────────────────
  test "registration form renders the list-style picker with a hidden school field" do
    get new_registration_path

    assert_response :success
    assert_select "input[type=hidden][name='school_id'][data-school-picker-target='school']", count: 1
    assert_select "ul[data-school-picker-target='results']", count: 1
    assert_select "input[data-school-picker-target='query']", count: 1
    # 이름검색을 select 옵션 교체가 아니라 클릭 목록으로 대체했다(회귀 가드).
    assert_select "select[name='school_id']", count: 0
    assert_select "select[data-school-picker-target='classroom']", count: 0
  end

  # ── 학생 로그인 폼(스코프 학급 select 포함) ────────────────────────────
  test "student login form renders the list-style picker plus a scoped classroom dropdown" do
    get student_login_path

    assert_response :success
    assert_select "input[type=hidden][name='school_id'][data-school-picker-target='school']", count: 1
    assert_select "ul[data-school-picker-target='results']", count: 1
    assert_select "select[data-school-picker-target='classroom']", count: 1
    assert_select "select[name='school_id']", count: 0
  end

  # ── JS 목록이 소비하는 검색 계약 ──────────────────────────────────────
  test "name search returns the matching school for the clickable list" do
    get schools_search_path, params: { q: "목록피커" }

    assert_response :success
    body = response.parsed_body
    assert_equal 1, body.size
    assert_equal @school.id, body.first["id"], "결과 항목의 id 가 hidden school_id 로 세팅된다"
    assert_equal "목록피커초등학교", body.first["name"]
  end

  # ── 선택 후 학급 캐스케이딩 계약(학생 폼) ──────────────────────────────
  test "selecting a school loads only that school's classrooms" do
    other = School.create!(name: "다른피커초")
    Classroom.create!(school: other, grade: 6, class_no: 2)

    get school_classrooms_path(id: @school.id)

    assert_response :success
    body = response.parsed_body
    assert_equal [ "4학년 1반" ], body.map { |room| room["label"] }, "선택 학교 학급만 로드"
  end

  # ── 선택→제출 종단(클릭이 세팅한 school_id 로 로그인) ───────────────────
  test "submitting with the selected school_id logs the student in" do
    post student_login_path, params: {
      school_id: @school.id, classroom_id: @classroom.id, name: "피커학생", password: "password"
    }

    assert_redirected_to root_path
    assert_equal @student.id, session[:user_id]
  end
end
