require "test_helper"

# 챌린지 e2e: 조회·참여(학생) + 관리 CRUD(교직원) + 학교 경계.
# scope·school_id 는 폼 입력이 아니라 역할에서 파생(총괄=전국, 교사·사서·교무=우리 학교)한다.
class ChallengesTest < ActionDispatch::IntegrationTest
  setup do
    @school_a = School.create!(name: "챌린지A초")
    @school_b = School.create!(name: "챌린지B초")
    @room_a = Classroom.create!(school: @school_a, grade: 5, class_no: 1)

    @student = User.create!(school: @school_a, classroom: @room_a, name: "챌린지학생", role: :student, password: "password")
    @teacher_a = User.create!(school: @school_a, name: "챌린지교사A", role: :teacher, password: "password")
    @teacher_b = User.create!(school: @school_b, name: "챌린지교사B", role: :teacher, password: "password")
    @librarian_a = User.create!(school: @school_a, name: "챌린지사서A", role: :librarian, password: "password")
    @school_admin_a = User.create!(school: @school_a, name: "챌린지교무A", role: :school_admin, password: "password")
    @superadmin = User.create!(name: "챌린지총괄", role: :superadmin, password: "password")

    @global = Challenge.create!(title: "전국 챌린지", scope: :global)
    @school_a_challenge = Challenge.create!(title: "A학교 챌린지", scope: :school, school: @school_a)
    @school_b_challenge = Challenge.create!(title: "B학교 챌린지", scope: :school, school: @school_b)
  end

  # ---- 학생: 조회·참여, 관리 불가 ----

  test "student home surfaces a challenge entry card" do
    login_as @student
    get root_path
    assert_response :success
    assert_select "a[href=?]", challenges_path, text: /챌린지/
  end

  test "student sees joinable challenges and a join button but no create button" do
    login_as @student
    get challenges_path
    assert_response :success
    assert_match "전국 챌린지", response.body
    assert_match "A학교 챌린지", response.body
    assert_no_match "B학교 챌린지", response.body           # 학교 경계: 다른 학교 챌린지는 안 보임
    assert_select "a[href=?]", new_challenge_path, count: 0  # 학생에겐 만들기 버튼 없음
  end

  test "student can join a challenge which sets the session flag" do
    login_as @student
    post join_challenge_path(@global)
    assert_redirected_to new_report_path
    assert_equal @global.id, session[:active_challenge_id]
  end

  test "student cannot reach new or create" do
    login_as @student
    get new_challenge_path
    assert_response :forbidden

    assert_no_difference -> { Challenge.count } do
      post challenges_path, params: { challenge: { title: "학생이만든것" } }
    end
    assert_response :forbidden
  end

  # ---- 교사: 우리 학교 챌린지 관리 ----

  test "teacher creates a school-scoped challenge for their own school" do
    login_as @teacher_a
    assert_difference -> { Challenge.count }, 1 do
      post challenges_path, params: { challenge: { title: "우리반 여름 챌린지", starts_on: "2026-07-20", ends_on: "2026-08-20" } }
    end
    created = Challenge.order(:created_at).last
    assert_redirected_to challenge_path(created)
    assert created.school?
    assert_equal @school_a.id, created.school_id
    assert_equal "우리반 여름 챌린지", created.title
  end

  test "teacher can create a challenge with multi-book goals and reward" do
    book_a = Book.create!(title: "챌린지책A", category: :recommended)
    book_b = Book.create!(title: "챌린지책B", category: :recommended)
    login_as @teacher_a
    post challenges_path, params: { challenge: {
      title: "여러 책 챌린지", reward_points: 30,
      goals: { approved_reports: 2 },
      goal_books: { approved_reports: { ids: [ book_a.id, book_b.id ] } }
    } }
    created = Challenge.order(:created_at).last
    assert_equal 30, created.reward_points
    goal = created.challenge_goals.find_by(goal_type: :approved_reports)
    assert_equal 2, goal.target_count
    assert_equal [ book_a.id, book_b.id ].sort, goal.books.map(&:id).sort
  end

  test "teacher can edit and delete their own school's challenge" do
    login_as @teacher_a
    get edit_challenge_path(@school_a_challenge)
    assert_response :success

    patch challenge_path(@school_a_challenge), params: { challenge: { title: "A학교 챌린지(수정)" } }
    assert_redirected_to challenge_path(@school_a_challenge)
    assert_equal "A학교 챌린지(수정)", @school_a_challenge.reload.title

    assert_difference -> { Challenge.count }, -1 do
      delete challenge_path(@school_a_challenge)
    end
    assert_redirected_to challenges_path
  end

  test "teacher cannot manage a global challenge" do
    login_as @teacher_a
    get edit_challenge_path(@global)
    assert_response :forbidden

    patch challenge_path(@global), params: { challenge: { title: "탈취시도" } }
    assert_response :forbidden
    assert_equal "전국 챌린지", @global.reload.title
  end

  test "teacher cannot manage another school's challenge" do
    login_as @teacher_b
    assert_no_difference -> { Challenge.count } do
      delete challenge_path(@school_a_challenge)
    end
    assert_response :forbidden
  end

  test "a staff-created challenge ignores forged scope and school_id params" do
    login_as @teacher_a
    post challenges_path, params: { challenge: { title: "위조시도", scope: "global", school_id: @school_b.id } }
    created = Challenge.order(:created_at).last
    assert created.school?                       # global 로 위조 못 함
    assert_equal @school_a.id, created.school_id  # 남의 학교로 위조 못 함
  end

  # ---- 사서·교무: 우리 학교 챌린지 관리 ----

  test "librarian and school_admin can create their own school's challenge" do
    [ @librarian_a, @school_admin_a ].each do |staff|
      login_as staff
      assert_difference -> { Challenge.count }, 1 do
        post challenges_path, params: { challenge: { title: "#{staff.role} 챌린지" } }
      end
      created = Challenge.order(:created_at).last
      assert created.school?
      assert_equal @school_a.id, created.school_id
    end
  end

  # ---- 총괄: 전국 챌린지 + 전권 ----

  test "superadmin creates a global challenge" do
    login_as @superadmin
    assert_difference -> { Challenge.count }, 1 do
      post challenges_path, params: { challenge: { title: "전국 독서왕" } }
    end
    created = Challenge.order(:created_at).last
    assert created.global?
    assert_nil created.school_id
  end

  test "superadmin can edit and delete any school's challenge" do
    login_as @superadmin
    patch challenge_path(@school_b_challenge), params: { challenge: { title: "총괄이수정" } }
    assert_redirected_to challenge_path(@school_b_challenge)
    assert_equal "총괄이수정", @school_b_challenge.reload.title

    assert_difference -> { Challenge.count }, -1 do
      delete challenge_path(@school_b_challenge)
    end
  end

  # ---- 진입점(교직원 대시보드/콘솔) ----

  test "teacher console nav links to challenges" do
    login_as @teacher_a
    get teacher_dashboard_path
    assert_response :success
    assert_select "a[href=?]", challenges_path
  end

  test "librarian and school_admin dashboards link to challenges" do
    login_as @librarian_a
    get root_path
    assert_response :success
    assert_select "a[href=?]", challenges_path

    login_as @school_admin_a
    get root_path
    assert_response :success
    assert_select "a[href=?]", challenges_path
  end

  # ---- 소개글(description) 저장·재표시 ----

  test "challenge create and update persist the description and redisplay it in the edit form" do
    login_as @teacher_a
    post challenges_path, params: { challenge: { title: "설명 있는 챌린지", description: "매주 한 권씩 읽어요" } }
    created = Challenge.order(:created_at).last
    assert_equal "매주 한 권씩 읽어요", created.description

    # 수정 폼에 소개글 textarea 가 값과 함께 다시 채워진다.
    get edit_challenge_path(created)
    assert_response :success
    assert_select "textarea[name=?]", "challenge[description]"
    assert_match "매주 한 권씩 읽어요", response.body

    # 수정으로 소개글이 갱신된다.
    patch challenge_path(created), params: { challenge: { title: created.title, description: "규칙이 바뀌었어요" } }
    assert_equal "규칙이 바뀌었어요", created.reload.description
  end

  # ---- 목록 카드: 학생 진행상황 + stretched-link + 버튼 동작 ----

  test "student challenge index shows own progress on active goaled challenges" do
    goaled = Challenge.create!(title: "진행 챌린지", scope: :global)
    goaled.challenge_goals.create!(goal_type: :approved_reports, target_count: 2)
    @student.reports.create!(classroom: @room_a, book_title: "읽은 책", reviewed: true)

    login_as @student
    get challenges_path
    assert_response :success
    assert_select ".progress-bar"
    assert_match "1/2", response.body
  end

  test "challenge index cards use a stretched title link while the join button stays operable" do
    login_as @student
    get challenges_path
    assert_response :success
    # 카드 제목이 상세로 가는 링크(중복 '상세' 버튼은 제거)
    assert_select "a[href=?]", challenge_path(@global), text: "전국 챌린지"
    assert_select "a[href=?]", challenge_path(@global), count: 1
    assert_match "after:absolute after:inset-0", response.body
    # 참여 버튼(button_to → form)은 stretched 링크 위에서 독립 동작
    assert_select "form[action=?]", join_challenge_path(@global)
  end

  test "manager challenge cards keep working edit and delete controls beside the stretched link" do
    login_as @teacher_a
    get challenges_path
    assert_response :success
    # A학교 챌린지는 교사A가 관리 가능 — 수정 링크·삭제 폼 유지
    assert_select "a[href=?]", edit_challenge_path(@school_a_challenge)
    assert_select "form[action=?]", challenge_path(@school_a_challenge)
    # 카드 전체 클릭용 stretched 제목 링크도 함께 존재
    assert_select "a[href=?]", challenge_path(@school_a_challenge), text: "A학교 챌린지"
  end

  # ---- 상세 하단 책 목록 → reading_activity 링크 ----
  # 하단 책 목록은 shared/_activity_book_list 파셜(worker-2 담당)에 의존한다.

  test "challenge detail bottom lists goal books linking to reading activity" do
    book = Book.create!(title: "챌린지 지정도서", category: :recommended)
    goaled = Challenge.create!(title: "지정도서 챌린지", scope: :global)
    goal = goaled.challenge_goals.create!(goal_type: :approved_reports, target_count: 1)
    goal.books << book

    login_as @student
    get challenge_path(goaled)
    assert_response :success
    assert_match "챌린지 지정도서", response.body
    assert_select "a[href=?]", reading_activity_path(book_id: book.id)
  end
end
