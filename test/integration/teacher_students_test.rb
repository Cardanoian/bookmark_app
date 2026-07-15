require "test_helper"

# P6.2 교사 학생 관리: 추가(해시 비밀번호)·초기화·수동 포인트 지급·경계 인가.
class TeacherStudentsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "학생관리학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "학생담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)

    @other_classroom = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @other_teacher = User.create!(school: @school, classroom: @other_classroom, name: "타담임", role: :teacher, password: "password")
    @other_classroom.update!(teacher: @other_teacher)

    @student = User.create!(school: @school, classroom: @classroom, name: "관리학생", password: "password")
  end

  test "index lists the담임's students" do
    login_as @teacher
    get teacher_students_path
    assert_response :success
    assert_match @student.name, response.body
  end

  test "create adds a student with a random temporary password surfaced to the teacher" do
    login_as @teacher
    assert_difference -> { User.count }, 1 do
      post teacher_students_path, params: { student: { name: "신규학생" } }
    end

    created = User.find_by(name: "신규학생")
    assert created.student?
    assert_equal @classroom.id, created.classroom_id

    temp = flash[:notice][/임시 비밀번호 ([A-Za-z0-9]+)/, 1]
    assert temp.present?, "임시 비밀번호가 안내 메시지에 노출돼야 한다"
    assert_not_equal "1234", temp, "기본 비밀번호 1234 는 더 이상 쓰지 않는다"
    assert created.authenticate(temp), "안내된 임시 비밀번호로 인증돼야 한다"
    assert_not_equal temp, created.password_digest, "비밀번호는 평문이 아니라 해시로 저장돼야 한다"
  end

  test "reset_password resets to a random temporary password surfaced to the teacher" do
    @student.update!(password: "changed99")
    login_as @teacher
    post reset_password_teacher_student_path(@student)

    temp = flash[:notice][/임시 비밀번호 ([A-Za-z0-9]+)/, 1]
    assert temp.present?, "임시 비밀번호가 안내 메시지에 노출돼야 한다"
    assert_not_equal "1234", temp
    assert @student.reload.authenticate(temp)
    assert_not @student.authenticate("changed99")
  end

  test "give_points increments the student's points via award_points" do
    before = @student.points
    login_as @teacher
    post give_points_teacher_student_path(@student), params: { points: 15 }

    assert_equal before + 15, @student.reload.points
  end

  test "destroy removes the student" do
    login_as @teacher
    assert_difference -> { User.count }, -1 do
      delete teacher_student_path(@student)
    end
  end

  test "a non-담임 teacher cannot manage this classroom's student" do
    login_as @other_teacher
    post give_points_teacher_student_path(@student), params: { points: 15 }
    assert_response :forbidden
    assert_equal 0, @student.reload.points
  end

  test "a student is forbidden from student management" do
    login_as @student
    get teacher_students_path
    assert_response :forbidden
  end

  test "a librarian is forbidden from student management" do
    librarian = User.create!(school: @school, name: "관리사서", role: :librarian, password: "password")
    login_as librarian
    get teacher_students_path
    assert_response :forbidden
  end

  private
end
