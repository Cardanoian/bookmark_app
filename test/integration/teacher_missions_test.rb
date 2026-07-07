require "test_helper"

# P6.2 교사 미션 CRUD + 경계 인가.
class TeacherMissionsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "미션학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "미션담임", role: :teacher, password: "password", approved: true)
    @classroom.update!(teacher: @teacher)

    @other_classroom = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @other_teacher = User.create!(school: @school, classroom: @other_classroom, name: "미션타담임", role: :teacher, password: "password", approved: true)
    @other_classroom.update!(teacher: @other_teacher)

    @student = User.create!(school: @school, classroom: @classroom, name: "미션학생", password: "password")
  end

  test "create makes a mission for the담임's classroom" do
    login_as @teacher
    assert_difference -> { Mission.count }, 1 do
      post teacher_missions_path, params: { mission: { title: "가을 독서 미션", start_date: "2026-09-01", end_date: "2026-09-30" } }
    end
    assert_equal @classroom.id, Mission.order(:created_at).last.classroom_id
  end

  test "index lists missions" do
    Mission.create!(classroom: @classroom, title: "겨울 미션")
    login_as @teacher
    get teacher_missions_path
    assert_response :success
    assert_match "겨울 미션", response.body
  end

  test "update edits a mission" do
    mission = Mission.create!(classroom: @classroom, title: "원제목")
    login_as @teacher
    patch teacher_mission_path(mission), params: { mission: { title: "새제목" } }
    assert_equal "새제목", mission.reload.title
  end

  test "destroy removes a mission" do
    mission = Mission.create!(classroom: @classroom, title: "삭제미션")
    login_as @teacher
    assert_difference -> { Mission.count }, -1 do
      delete teacher_mission_path(mission)
    end
  end

  test "a non-담임 teacher cannot edit another classroom's mission" do
    mission = Mission.create!(classroom: @classroom, title: "보호미션")
    login_as @other_teacher
    patch teacher_mission_path(mission), params: { mission: { title: "침입" } }
    assert_response :forbidden
    assert_equal "보호미션", mission.reload.title
  end

  test "a student is forbidden from missions management" do
    login_as @student
    get teacher_missions_path
    assert_response :forbidden
  end

  private

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
