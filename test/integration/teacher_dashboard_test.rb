require "test_helper"

# P6.1 교사 대시보드: 5축 평균·방사형 SVG·A비율·검토대기·약점 인사이트.
class TeacherDashboardTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "대시보드학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "대시담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "대시학생", password: "password")
    @student.update!(points: 40, experience: 80)

    rubric = { "content" => 5, "emotion" => 4, "life" => 4, "structure" => 3, "spelling" => 2 }
    @a1 = Report.create!(user: @student, classroom: @classroom, book_title: "책1", rubric: rubric, avg: 4.2, level: "A", ai_status: :done, reviewed: true)
    @a2 = Report.create!(user: @student, classroom: @classroom, book_title: "책2", rubric: rubric, avg: 4.1, level: "A", ai_status: :done, reviewed: true)
    @b1 = Report.create!(user: @student, classroom: @classroom, book_title: "책3", rubric: rubric, avg: 3.0, level: "B", ai_status: :done, reviewed: false)
  end

  test "dashboard renders the radar svg and 5축 averages" do
    login_as @teacher
    get teacher_dashboard_path

    assert_response :success
    assert_match "<svg", response.body
    assert_match "<polygon", response.body
    assert_match ReadingDomain::AXIS_LABELS[:content], response.body
  end

  test "dashboard reports correct A ratio and pending count" do
    login_as @teacher
    get teacher_dashboard_path

    assert_response :success
    assert_match "67%", response.body # A 2 of 3 scored
    assert_match "검토 대기", response.body
    assert_match "평균 경험치", response.body
    assert_match "80.0", response.body
  end

  test "dashboard surfaces the weakest axis insight" do
    login_as @teacher
    get teacher_dashboard_path

    assert_response :success
    # 가장 낮은 축은 맞춤법(2점) → 성취기준 코드 노출
    assert_match ReadingDomain::ACHIEVEMENT_STANDARDS[:spelling], response.body
  end

  # 약점 인사이트는 담임 학급의 학년군 기준을 보여야 한다(3학년 → g34, 6학년 기준 미노출).
  test "weakness insight uses the classroom grade band (g34 for grade 3)" do
    school = School.create!(name: "3학년학교")
    classroom = Classroom.create!(school: school, grade: 3, class_no: 1)
    teacher = User.create!(school: school, classroom: classroom, name: "3담임", role: :teacher, password: "password")
    classroom.update!(teacher: teacher)
    student = User.create!(school: school, classroom: classroom, name: "3학생", password: "password")
    rubric = { "content" => 5, "emotion" => 4, "life" => 4, "structure" => 3, "spelling" => 2 }
    Report.create!(user: student, classroom: classroom, book_title: "책", rubric: rubric, avg: 3.6, level: "B", ai_status: :done, reviewed: true)

    login_as teacher
    get teacher_dashboard_path

    assert_response :success
    # 성취기준: g34 노출, g56 미노출
    assert_match ReadingDomain.achievement_standards(:g34)[:spelling], response.body
    assert_no_match(/#{Regexp.escape(ReadingDomain.achievement_standards(:g56)[:spelling])}/, response.body)
    # 추천활동도 밴드화됐는지(성취기준만 밴드화하는 비대칭 수정 방지)
    assert_match ReadingDomain.recommended_activities(:g34)[:spelling], response.body
    assert_no_match(/#{Regexp.escape(ReadingDomain.recommended_activities(:g56)[:spelling])}/, response.body)
  end

  # 여러 밴드가 섞인 담임(2학년+5학년)은 g56 종착 폴백(전교 통계 관례). 아동 대면 g12 age-safety 폴백과 무관.
  test "weakness insight falls back to g56 when classrooms span multiple bands" do
    school = School.create!(name: "혼합학교")
    teacher = User.create!(school: school, name: "혼합담임", role: :teacher, password: "password")
    c2 = Classroom.create!(school: school, grade: 2, class_no: 1, teacher: teacher) # g12
    c5 = Classroom.create!(school: school, grade: 5, class_no: 1, teacher: teacher) # g56
    rubric = { "content" => 5, "emotion" => 4, "life" => 4, "structure" => 3, "spelling" => 2 }
    [ c2, c5 ].each_with_index do |classroom, i|
      student = User.create!(school: school, classroom: classroom, name: "학생#{i}", password: "password")
      Report.create!(user: student, classroom: classroom, book_title: "책#{i}", rubric: rubric, avg: 3.6, level: "B", ai_status: :done, reviewed: true)
    end

    login_as teacher
    get teacher_dashboard_path

    assert_response :success
    assert_match ReadingDomain.achievement_standards(:g56)[:spelling], response.body
    assert_no_match(/#{Regexp.escape(ReadingDomain.achievement_standards(:g12)[:spelling])}/, response.body)
  end

  test "dashboard improvement average matches the SQL aggregate" do
    # improvement 기록이 있는 리포트 2개 → 평균 향상도 = (0.5 + 1.5) / 2 = 1.0
    Report.create!(user: @student, classroom: @classroom, book_title: "고쳐1", improvement: 0.5, avg: 3.0, level: "B", ai_status: :done)
    Report.create!(user: @student, classroom: @classroom, book_title: "고쳐2", improvement: 1.5, avg: 3.0, level: "B", ai_status: :done)
    login_as @teacher

    get teacher_dashboard_path
    assert_response :success
    assert_match "1.0점", response.body
  end

  # 무게이트 롤아웃 사후 검토(교사 알림): 담임 학급 학생이 신고한 온디맨드 게임 콘텐츠를 노출한다.
  test "dashboard surfaces reported on-demand game content from the teacher's students" do
    book = Book.create!(title: "신고책", category: :recommended)
    quiz = Quiz.create!(title: "온디맨드 mcq", created_by: @teacher, book: book, scope: :global,
                        published: true, origin: :system, content_axis: :mcq, band: :g56, generation_status: :ready)
    QuizReport.create!(quiz: quiz, user: @student)

    login_as @teacher
    get teacher_dashboard_path
    assert_response :success
    assert_match "신고된 게임 콘텐츠", response.body
    assert_match "신고책", response.body
  end

  test "a student is forbidden from the teacher dashboard" do
    login_as @student
    get teacher_dashboard_path
    assert_response :forbidden
  end

  test "a librarian is forbidden from the teacher dashboard" do
    librarian = User.create!(school: @school, name: "사서", role: :librarian, password: "password")
    login_as librarian
    get teacher_dashboard_path
    assert_response :forbidden
  end

  private
end
