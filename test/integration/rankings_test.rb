require "test_helper"

# P4.10 — 랭킹 페이지 렌더링(탭별) + 포디움 노출.
class RankingsTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    @school = School.create!(name: "랭킹뷰초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @s1 = User.create!(school: @school, classroom: @classroom, name: "랭킹일등", points: 300, password: "password")
    @s2 = User.create!(school: @school, classroom: @classroom, name: "랭킹이등", points: 100, password: "password")
  end

  test "each ranking tab renders successfully" do
    login_as @s1

    %w[class school nation challenge hall].each do |tab|
      get rankings_path(tab: tab)
      assert_response :success, "tab=#{tab} 렌더링 실패"
    end
  end

  test "class tab shows the podium and classroom members" do
    login_as @s1

    get rankings_path(tab: "class")

    assert_response :success
    assert_match "랭킹일등", response.body
    assert_match "랭킹이등", response.body
    assert_match "🥇", response.body
  end

  test "an unknown tab falls back to the class ranking" do
    login_as @s1

    get rankings_path(tab: "bogus")

    assert_response :success
    assert_select "nav a", text: "우리 반"
  end

  private

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
