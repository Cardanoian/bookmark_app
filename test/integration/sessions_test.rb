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

  test "an unapproved teacher is blocked from logging in" do
    teacher = User.create!(
      school: @school, classroom: @classroom, name: "미승인담임",
      role: :teacher, password: "password", approved: false
    )

    post session_path, params: {
      school_id: teacher.school_id, classroom_id: teacher.classroom_id,
      name: teacher.name, password: "password"
    }

    assert_response :forbidden
    assert_nil session[:user_id]
  end

  test "login attempts are throttled after the rate limit" do
    # 테스트 캐시는 :null_store 라 카운팅이 안 되므로, 스로틀 저장소를 카운팅 가능한
    # 인메모리 스토어로 교체해 검증한다(teardown 에서 원복). config/environments/test.rb 는 건드리지 않는다.
    SessionsController::RATE_LIMIT_STORE.target = ActiveSupport::Cache::MemoryStore.new

    10.times do
      post session_path, params: {
        school_id: @school.id, classroom_id: @classroom.id,
        name: "로그인학생", password: "wrong-password"
      }
    end
    assert_response :unprocessable_entity, "10회째까지는 스로틀되지 않아야 한다"

    post session_path, params: {
      school_id: @school.id, classroom_id: @classroom.id,
      name: "로그인학생", password: "password"
    }
    assert_redirected_to new_session_path
    assert_nil session[:user_id], "스로틀된 요청은 로그인시키지 않아야 한다"
  end

  teardown do
    SessionsController::RATE_LIMIT_STORE.target = Rails.cache
  end
end
