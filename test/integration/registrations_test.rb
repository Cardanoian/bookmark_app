require "test_helper"

class RegistrationsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "가입초등학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
  end

  test "student registration creates a student and signs in" do
    assert_difference "User.count", 1 do
      post registrations_path, params: {
        role: "student", school_id: @school.id, classroom_id: @classroom.id,
        name: "학생가입", password: "password"
      }
    end

    user = User.find_by(name: "학생가입")
    assert user.student?
    assert_equal @classroom.id, user.classroom_id
    assert_redirected_to root_path
    assert_equal user.id, session[:user_id]
  end

  test "teacher registration creates a teacher and assigns the classroom" do
    assert_difference "User.count", 1 do
      post registrations_path, params: {
        role: "teacher", school_id: @school.id,
        name: "교사가입", password: "password", grade: 5, class_no: 2
      }
    end

    user = User.find_by(name: "교사가입")
    assert user.teacher?
    classroom = Classroom.find_by(school: @school, grade: 5, class_no: 2)
    assert_equal user, classroom.teacher
    assert_equal classroom.id, user.classroom_id
    assert_redirected_to root_path
  end

  test "admin roles are rejected and no user is created" do
    %w[school_admin librarian superadmin].each do |role|
      assert_no_difference "User.count" do
        post registrations_path, params: {
          role: role, school_id: @school.id, name: "가짜관리자", password: "password"
        }
      end
      assert_redirected_to new_registration_path
    end
  end
end
