require "test_helper"

# P6.2 교사 루브릭 가중치: update 가 classroom.rubric_weights 에 반영 + 경계 인가.
class TeacherRubricConfigTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "루브릭학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "루브릭담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "루브릭학생", password: "password")
  end

  test "edit renders the current weights" do
    login_as @teacher
    get edit_teacher_rubric_config_path
    assert_response :success
    assert_match ReadingDomain::AXIS_LABELS[:content], response.body
  end

  test "update changes the classroom rubric weights" do
    login_as @teacher
    patch teacher_rubric_config_path(classroom_id: @classroom.id), params: {
      rubric_config: { weights: { content: 3, emotion: 2, life: 5, structure: 1, spelling: 1 }, emphasis: "life" }
    }

    weights = @classroom.reload.rubric_weights
    assert_equal 3, weights[:content]
    assert_equal 5, weights[:life]
    assert_equal "life", @classroom.rubric_emphasis
  end

  test "a student is forbidden from rubric config" do
    login_as @student
    get edit_teacher_rubric_config_path
    assert_response :forbidden
  end

  private
end
