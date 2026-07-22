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
    assert_match "0XP", response.body

    assert_select "form[action=?]", teacher_students_path do
      assert_select "input[type=?][name=?][minlength=?][required]", "password", "student[password]", "6"
    end
    assert_select "form[action=?]", reset_password_teacher_student_path(@student) do
      assert_select "input[type=?][name=?][minlength=?][required]", "password", "student[password]", "6"
    end
  end

  test "create adds a student with the teacher supplied password" do
    login_as @teacher
    password = "abc123"
    assert_difference -> { User.count }, 1 do
      post teacher_students_path, params: { student: { name: "신규학생", password: password } }
    end

    created = User.find_by(name: "신규학생")
    assert created.student?
    assert_equal @classroom.id, created.classroom_id
    assert created.authenticate(password), "교사가 입력한 비밀번호로 인증돼야 한다"
    assert_not_equal password, created.password_digest, "비밀번호는 평문이 아니라 해시로 저장돼야 한다"
    assert_not_includes flash[:notice], password
  end

  test "create rejects blank whitespace-only and short passwords" do
    login_as @teacher

    [ "", "      ", "12345" ].each_with_index do |password, index|
      assert_no_difference -> { User.count } do
        post teacher_students_path,
             params: { student: { name: "거부학생#{index}", password: password } }
      end
      assert flash[:alert].present?
    end
  end

  test "reset_password uses the teacher supplied password" do
    @student.update!(password: "changed99")
    login_as @teacher
    password = "new123"
    post reset_password_teacher_student_path(@student), params: { student: { password: password } }

    assert @student.reload.authenticate(password)
    assert_not @student.authenticate("changed99")
    assert_not_equal password, @student.password_digest
    assert_not_includes flash[:notice], password
  end

  test "reset_password rejects blank whitespace-only and short passwords without changing the password" do
    @student.update!(password: "changed99")
    login_as @teacher

    [ "", "      ", "12345" ].each do |password|
      post reset_password_teacher_student_path(@student), params: { student: { password: password } }

      assert @student.reload.authenticate("changed99")
      assert flash[:alert].present?
    end
  end

  test "give_points increments the student's points and experience via award_points" do
    points_before = @student.points
    experience_before = @student.experience
    login_as @teacher
    post give_points_teacher_student_path(@student), params: { points: 15 }

    @student.reload
    assert_equal points_before + 15, @student.points
    assert_equal experience_before + 15, @student.experience
    assert_match "15포인트와 15경험치를 지급", flash[:notice]
  end

  test "give_points rejects a non-positive amount without changing either balance" do
    login_as @teacher
    post give_points_teacher_student_path(@student), params: { points: -10 }

    assert_equal 0, @student.reload.points
    assert_equal 0, @student.experience
    assert_match "1 이상의 정수", flash[:alert]
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
    assert_equal 0, @student.experience
  end

  test "a non-담임 teacher cannot reset this classroom student's password" do
    login_as @other_teacher
    post reset_password_teacher_student_path(@student), params: { student: { password: "new123" } }

    assert_response :forbidden
    assert @student.reload.authenticate("password")
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
