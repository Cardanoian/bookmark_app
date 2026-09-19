require "test_helper"

class DashboardRoleTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "역할대시초등학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
  end

  test "student lands on the student dashboard" do
    login_as create_user(name: "역할학생", classroom: @classroom)
    get root_path
    assert_response :success
    assert_select "nav", text: /내 서재/
    assert_match "학생", response.body
  end

  test "teacher lands on the teacher console" do
    teacher = create_user(name: "역할교사", role: :teacher, classroom: @classroom)
    @classroom.update!(teacher: teacher)
    login_as teacher
    get root_path
    assert_response :success
    assert_match "교사 대시보드", response.body
    assert_match "학생관리", response.body
  end

  test "school_admin lands on the school admin dashboard" do
    login_as create_user(name: "역할교무", role: :school_admin, classroom: nil)
    get root_path
    assert_response :success
    assert_match "교무관리자", response.body
  end

  test "librarian lands on the librarian dashboard" do
    login_as create_user(name: "역할사서", role: :librarian, classroom: nil)
    get root_path
    assert_response :success
    assert_match "도서관 담당", response.body
  end

  # 교무관리자·사서 홈의 메뉴는 링크 없는 글자였다("전교 통계 / 계정 관리", "도서관 / 인기 대출") —
  # 홈에서 역할 전용 화면으로 갈 길이 없었고, 교무관리자에게 없는 "계정 관리"를 가리켰다.
  # 홈의 진입 링크가 실제 라우트를 가리키고, 그 역할이 그 화면을 열 수 있어야(200) 한다.
  test "school_admin home links to the school admin tools it can open" do
    login_as create_user(name: "링크교무", role: :school_admin, classroom: nil)
    get root_path
    assert_response :success

    assert_no_match "계정 관리", response.body, "교무관리자에게 없는 기능을 가리키지 않는다"
    [ school_admin_stats_path, school_admin_neis_path, challenges_path ].each do |path|
      assert_select "nav[aria-label=?] a[href=?]", "교무관리자 메뉴", path, count: 1
      get path
      assert_response :success, "교무관리자가 #{path} 를 열 수 있어야 한다"
      get root_path
    end
  end

  test "librarian home links to the librarian tools it can open" do
    login_as create_user(name: "링크사서", role: :librarian, classroom: nil)
    get root_path
    assert_response :success

    [ librarian_dashboard_path, librarian_loans_path, librarian_events_path, challenges_path ].each do |path|
      assert_select "nav[aria-label=?] a[href=?]", "사서 메뉴", path, count: 1
      get path
      assert_response :success, "사서가 #{path} 를 열 수 있어야 한다"
      get root_path
    end
  end

  test "superadmin is redirected to the admin console" do
    admin = User.create!(name: "역할총괄", role: :superadmin, password: "password")
    login_as admin
    get root_path
    assert_redirected_to admin_root_path
    follow_redirect!
    assert_response :success
    assert_match "총괄관리자", response.body
    assert_equal admin.id, session[:user_id]
  end

  # 로그아웃은 전역 헤더 밴드가 유일한 지면이다. 예전에는 각 대시보드 화면이 자기 버튼을 그려
  # 7곳에 흩어져 있었고, 그 화면을 벗어나면 로그아웃할 길이 없었다. 이제 어느 화면이든 정확히
  # 1개여야 한다 — 0개면 갇히고, 2개면 admin 처럼 헤더와 화면이 중복으로 그리는 상태다.
  test "every role sees exactly one logout button, in the global header" do
    teacher = create_user(name: "로그아웃교사", role: :teacher, classroom: @classroom)
    @classroom.update!(teacher: teacher)
    admin = User.create!(name: "로그아웃총괄", role: :superadmin, password: "password")

    cases = {
      "학생" => create_user(name: "로그아웃학생", classroom: @classroom),
      "교사" => teacher,
      "교무" => create_user(name: "로그아웃교무", role: :school_admin, classroom: nil),
      "사서" => create_user(name: "로그아웃사서", role: :librarian, classroom: nil),
      "총괄" => admin
    }

    cases.each do |label, user|
      login_as user
      get root_path
      follow_redirect! while response.redirect?

      # 화면 읽기 프로그램·번역기가 한국어로 읽도록 레이아웃(application·admin)이 언어를 밝힌다.
      assert_select "html[lang=ko]", 1, "#{label}: 레이아웃이 lang=\"ko\" 를 밝혀야 한다"
      assert_select "header.app-header form[action=?][method=post]", session_path, count: 1,
                    message: "#{label}: 헤더에 로그아웃이 1개여야 한다"
      assert_select "header.app-header form[action=?] button.btn.btn-primary", session_path, count: 1,
                    message: "#{label}: 로그아웃은 브랜드 블루 필 버튼이어야 한다"
      assert_select "form[action=?][method=post]", session_path, count: 1,
                    message: "#{label}: 화면 전체에서 로그아웃은 1개여야 한다(중복 렌더 금지)"
    end
  end

  test "staff see their name in the header but no 마이페이지 link" do
    teacher = create_user(name: "헤더교사", role: :teacher, classroom: @classroom)
    @classroom.update!(teacher: teacher)
    login_as teacher
    get root_path

    assert_select "header.app-header", text: /헤더교사/
    assert_select "header.app-header a[href=?]", profile_path, count: 0,
                  message: "마이페이지는 학생 대상 화면이라 교직원에게 노출하지 않는다"
  end

  private

  def create_user(name:, classroom:, role: :student)
    User.create!(school: @school, classroom: classroom, name: name, role: role, password: "password")
  end
end
