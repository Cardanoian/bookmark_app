require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "로그인초등학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
    @user = User.create!(
      school: @school, classroom: @classroom, name: "로그인학생", password: "password"
    )
  end

  test "successful login redirects to root and sets the session" do
    post session_path, params: {
      school_id: @school.id, classroom_id: @classroom.id,
      name: "로그인학생", password: "password"
    }

    assert_redirected_to root_path
    assert_equal @user.id, session[:user_id]
  end

  test "bad credentials re-render the form with 422" do
    post session_path, params: {
      school_id: @school.id, classroom_id: @classroom.id,
      name: "로그인학생", password: "wrong-password"
    }

    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  test "logout resets the session" do
    post session_path, params: {
      school_id: @school.id, classroom_id: @classroom.id,
      name: "로그인학생", password: "password"
    }
    assert_equal @user.id, session[:user_id]

    delete session_path
    assert_redirected_to new_session_path
    assert_nil session[:user_id]
  end
end
