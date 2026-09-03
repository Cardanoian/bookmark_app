require "test_helper"

# 교사 학생별 통계(student-stats): 학급 표·정렬·학급 선택·학생 상세 렌더 + 학급 경계 인가.
class TeacherStudentStatsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "통계열람학교")
    @classroom = Classroom.create!(school: @school, grade: 4, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "통계담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)

    @other_classroom = Classroom.create!(school: @school, grade: 4, class_no: 2)
    @other_teacher = User.create!(school: @school, classroom: @other_classroom, name: "타담임", role: :teacher, password: "password")
    @other_classroom.update!(teacher: @other_teacher)
    @other_student = User.create!(school: @school, classroom: @other_classroom, name: "타반학생", password: "password")

    @book = Book.create!(title: "통계열람책", category: :recommended)
    @active = User.create!(school: @school, classroom: @classroom, name: "차활발", password: "password")
    @idle = User.create!(school: @school, classroom: @classroom, name: "가조용", password: "password")

    Report.create!(user: @active, classroom: @classroom, book: @book, body: "본문", reviewed: true, level: "A",
                   rubric: { content: 4, emotion: 4, life: 4, structure: 4, spelling: 4 }, submitted_at: Time.current)
    Report.create!(user: @active, classroom: @classroom, book: @book, body: "검토 대기 글", reviewed: false,
                   submitted_at: Time.current)
    GamePlay.create!(user: @active, book: @book, game_type: :quiz, played_on: Date.current)
  end

  test "index lists the 담임's students with their activity metrics" do
    login_as @teacher
    get teacher_student_stats_path

    assert_response :success
    assert_match @active.name, response.body
    assert_match @idle.name, response.body
    assert_no_match(/타반학생/, response.body, "타 학급 학생은 표에 없어야 한다")
    assert_select "a[href=?]", teacher_student_stat_path(@active)
    assert_match "아직 시작하지 않은 학생", response.body, "무활동 학생 명단을 표 위에 노출한다"
  end

  test "index sorts by the requested metric and falls back to name on 위조 값" do
    login_as @teacher

    get teacher_student_stats_path(sort: "approved")
    assert_response :success
    assert_equal [ @active.name, @idle.name ], table_student_order, "승인 독후감 내림차순이면 활동 학생이 먼저"

    get teacher_student_stats_path(sort: "'; DROP TABLE users; --")
    assert_response :success
    assert_equal [ @idle.name, @active.name ], table_student_order, "위조 정렬 값은 이름순 폴백(가조용 < 차활발)"
  end

  # `recent` 축은 Date 를 정렬 키로 넘기는데 예전 desc_by 가 `.to_f` 를 호출해 **헤더를 한 번
  # 누르면 500** 이었다(커버 테스트가 없어 오래 살아남았다). 9개 축 전부를 스모크로 묶는다.
  test "index renders for every whitelisted sort key" do
    login_as @teacher

    Teacher::StudentStatsController::SORTS.each do |sort|
      get teacher_student_stats_path(sort: sort)
      assert_response :success, "sort=#{sort} 에서 실패했다"
    end
  end

  test "index reverses the order when dir is flipped and keeps 이름 tiebreak" do
    login_as @teacher

    get teacher_student_stats_path(sort: "approved", dir: "desc")
    assert_response :success
    assert_equal [ @active.name, @idle.name ], table_student_order

    get teacher_student_stats_path(sort: "approved", dir: "asc")
    assert_response :success
    assert_equal [ @idle.name, @active.name ], table_student_order, "방향을 뒤집으면 순서도 뒤집힌다"

    get teacher_student_stats_path(sort: "approved", dir: "'; DROP TABLE users; --")
    assert_response :success
    assert_equal [ @active.name, @idle.name ], table_student_order, "위조 방향은 축 기본값(desc)으로 폴백"
  end

  test "index filters by 이름 검색 without leaking past the classroom boundary" do
    login_as @teacher

    get teacher_student_stats_path(q: "차활")
    assert_response :success
    assert_equal [ @active.name ], table_student_order
    assert_match "차활", response.body

    # 검색은 학급 경계 스코프 **위에만** 얹힌다 — 타 학급 학생은 이름이 맞아도 나오면 안 된다.
    get teacher_student_stats_path(q: "타반학생")
    assert_response :success
    assert_equal [], table_student_order
  end

  test "index escapes LIKE wildcards so % does not match everyone" do
    login_as @teacher

    get teacher_student_stats_path(q: "%")
    assert_response :success
    assert_equal [], table_student_order, "'%' 는 리터럴로 취급돼 아무도 매칭되지 않아야 한다"
  end

  # 정렬을 누를 때마다 검색이 풀리면 교사가 두 조작을 함께 쓸 수 없다.
  test "sort links carry the active 검색어" do
    login_as @teacher
    get teacher_student_stats_path(q: "차활", sort: "approved")

    assert_response :success
    assert_select "a[href*='q=%EC%B0%A8%ED%99%9C']", minimum: 1
  end

  test "index renders the 검색 form even for a teacher with a single classroom" do
    login_as @teacher
    get teacher_student_stats_path

    assert_response :success
    assert_select "select#classroom_id", count: 0, message: "단일 학급이면 학급 select 는 없다"
    assert_select "input#q", count: 1, message: "그래도 검색 입력은 있어야 한다"
  end

  test "index lets a 겸임 teacher switch between owned classrooms" do
    second = Classroom.create!(school: @school, grade: 5, class_no: 3, teacher: @teacher)
    second_student = User.create!(school: @school, classroom: second, name: "겸임반학생", password: "password")

    login_as @teacher
    get teacher_student_stats_path
    assert_response :success
    assert_select "select#classroom_id option", count: 2
    assert_equal [ @idle.name, @active.name ], table_student_order, "기본은 첫 학급"

    get teacher_student_stats_path(classroom_id: second.id)
    assert_response :success
    assert_equal [ second_student.name ], table_student_order
  end

  test "index rejects a classroom the teacher does not own" do
    login_as @teacher
    get teacher_student_stats_path(classroom_id: @other_classroom.id)
    assert_response :forbidden
  end

  test "show renders one student's report, game, mission and challenge record" do
    mission = Mission.create!(classroom: @classroom, created_by: @teacher, title: "겨울 독서 미션",
                              start_date: Date.current - 1, end_date: Date.current + 7)
    mission.mission_goals.create!(goal_type: :approved_reports, target_count: 3)
    mission.publish! # 학급 학생 자동 배정(AssignmentSync)

    challenge = Challenge.create!(title: "전국 독서 챌린지", scope: :global, starts_on: Date.current - 1)
    ChallengeParticipation.create!(challenge: challenge, user: @active, joined_at: Time.current)

    login_as @teacher
    get teacher_student_stat_path(@active)

    assert_response :success
    assert_match @active.name, response.body
    assert_match "겨울 독서 미션", response.body
    assert_match "전국 독서 챌린지", response.body
    assert_match "통계열람책", response.body
    assert_select "a[href=?]", teacher_review_path(Report.find_by(user: @active, reviewed: true))
    assert_match "독서 퀴즈", response.body, "게임 종류별 참여 분해를 보여 준다"
  end

  test "show works for a student with no activity at all" do
    login_as @teacher
    get teacher_student_stat_path(@idle)

    assert_response :success
    assert_match "아직 쓴 독후감이 없어요", response.body
    assert_match "아직 승인한 독후감이 없어서", response.body
  end

  test "show refuses a student outside the teacher's classroom" do
    login_as @teacher
    get teacher_student_stat_path(@other_student)
    assert_response :forbidden
  end

  test "students cannot reach the teacher stats screens" do
    login_as @active
    get teacher_student_stats_path
    assert_response :forbidden

    get teacher_student_stat_path(@active)
    assert_response :forbidden
  end

  test "teacher navigation and dashboard link to the stats screen" do
    login_as @teacher
    get teacher_dashboard_path
    assert_response :success
    assert_select "a[href=?]", teacher_student_stats_path

    get teacher_students_path
    assert_response :success
    assert_select "a[href=?]", teacher_student_stat_path(@active)
  end

  private

  # 표 본문의 학생 이름 순서(정렬 검증용). 표 위 "아직 시작하지 않은 학생" 안내와 섞이지 않도록
  # 본문 문자열 위치가 아니라 tbody 행에서만 읽는다.
  def table_student_order
    css_select("tbody tr td:first-child a").map { |node| node.text.strip }
  end
end
