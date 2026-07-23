require "test_helper"

class RankingPreferencesTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "닉네임학교")
    @classroom = Classroom.create!(school: @school, grade: 4, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "실명학생", password: "password")
  end

  test "a student without a nickname is forced to the preference page" do
    login_as @student, onboarded: false

    get root_path

    assert_redirected_to edit_ranking_preference_path
  end

  test "a student can choose a nickname and keep their ranking identity private" do
    login_as @student, onboarded: false

    patch ranking_preference_path, params: {
      user: { nickname: "조용한독서가", ranking_opted_in: "0" }
    }

    assert_redirected_to growth_path
    @student.reload
    assert_equal "조용한독서가", @student.nickname
    assert_not @student.ranking_opted_in?

    get rankings_path
    assert_response :success
    ranking_text = css_select("[id^='ranking_user_']").map(&:text).join(" ")
    assert_includes ranking_text, "비공개 학생"
    assert_not_includes ranking_text, @student.nickname
    assert_not_includes ranking_text, @student.name
  end

  test "ranking participation requires an explicit choice" do
    login_as @student, onboarded: false

    patch ranking_preference_path, params: { user: { nickname: "선택대기" } }

    assert_response :unprocessable_entity
    assert_nil @student.reload.nickname
    assert_match "선택", response.body
  end

  test "an opted-in student's nickname is shown while the real name is hidden" do
    peer = User.create!(
      school: @school, classroom: @classroom, name: "친구실명", nickname: "책구름",
      ranking_opted_in: true, points: 10, password: "password"
    )
    @student.update!(nickname: "책바람", ranking_opted_in: true)
    login_as @student

    get rankings_path(tab: "class")

    assert_response :success
    ranking_text = css_select("[id^='ranking_user_']").map(&:text).join(" ")
    assert_includes ranking_text, @student.nickname
    assert_includes ranking_text, peer.nickname
    assert_not_includes ranking_text, @student.name
    assert_not_includes ranking_text, peer.name
  end
end
