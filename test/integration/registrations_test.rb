require "test_helper"

# 0.1 공개 회원가입 = 교사 신청 전용 + 관리자 승인 게이트 + 학급 탈취 방지.
class RegistrationsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "가입초등학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
  end

  test "teacher signup creates an unapproved teacher and does not sign in" do
    assert_difference "User.count", 1 do
      post registrations_path, params: {
        role: "teacher", school_id: @school.id,
        name: "교사가입", password: "password", grade: 5, class_no: 2
      }
    end

    user = User.find_by(name: "교사가입")
    assert user.teacher?
    assert_not user.approved?, "신규 교사는 승인 대기(approved:false) 상태여야 한다"
    assert_nil session[:user_id], "가입 즉시 로그인되면 안 된다"
    assert_redirected_to new_session_path

    classroom = Classroom.find_by(school: @school, grade: 5, class_no: 2)
    assert_equal user, classroom.teacher
  end

  test "an unapproved teacher cannot log in until approved" do
    post registrations_path, params: {
      role: "teacher", school_id: @school.id,
      name: "미승인교사", password: "password", grade: 6, class_no: 1
    }
    teacher = User.find_by(name: "미승인교사")

    post session_path, params: {
      school_id: teacher.school_id, classroom_id: teacher.classroom_id,
      name: teacher.name, password: "password"
    }
    assert_response :forbidden
    assert_nil session[:user_id]

    teacher.update!(approved: true)
    post session_path, params: {
      school_id: teacher.school_id, classroom_id: teacher.classroom_id,
      name: teacher.name, password: "password"
    }
    assert_redirected_to root_path
    assert_equal teacher.id, session[:user_id]
  end

  test "signup cannot take over a classroom that already has a different teacher" do
    incumbent = User.create!(school: @school, classroom: @classroom, name: "기존담임", role: :teacher, password: "password", approved: true)
    @classroom.update!(teacher: incumbent)

    assert_no_difference "User.count" do
      post registrations_path, params: {
        role: "teacher", school_id: @school.id,
        name: "탈취시도교사", password: "password",
        grade: @classroom.grade, class_no: @classroom.class_no
      }
    end

    assert_equal incumbent.id, @classroom.reload.teacher_id, "기존 담임이 유지돼야 한다(탈취 실패)"
    assert_nil User.find_by(name: "탈취시도교사"), "탈취 시도는 교사 계정도 만들지 않아야 한다"
  end

  test "student self-registration is no longer available" do
    assert_no_difference "User.where(role: :student).count" do
      post registrations_path, params: {
        role: "student", school_id: @school.id, classroom_id: @classroom.id,
        name: "학생가입시도", password: "password"
      }
    end
    assert_nil session[:user_id]
  end

  test "role param is ignored — signups are always unapproved teachers" do
    %w[school_admin librarian superadmin student].each do |role|
      post registrations_path, params: {
        role: role, school_id: @school.id, name: "역할무시_#{role}", password: "password"
      }
      created = User.find_by(name: "역할무시_#{role}")
      assert created.teacher?, "어떤 role 파라미터든 교사로만 생성돼야 한다"
      assert_not created.approved?
    end
  end

  test "password shorter than six characters is rejected" do
    assert_no_difference "User.count" do
      post registrations_path, params: {
        role: "teacher", school_id: @school.id, name: "짧은비번교사", password: "12345"
      }
    end
    assert_response :unprocessable_entity
  end
end
