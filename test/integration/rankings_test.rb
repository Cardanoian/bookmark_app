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

  test "class ranking renders each student's active monster image" do
    species = MonsterSpecies.find_by!(key: "pup_1")
    monster = @s1.user_monsters.create!(monster_species: species)
    @s1.update!(active_monster: monster)
    login_as @s1

    get rankings_path(tab: "class")

    assert_response :success
    images = css_select("img[alt='#{species.name}']")
    assert_equal 2, images.size, "대표 몬스터가 포디움과 랭킹 행에 각각 이미지로 표시되어야 한다"
    images.each do |image|
      assert_match %r{/(?:assets|images)/monsters/pup_1(?:-[^/.]+)?\.webp}, image["src"]
    end
    assert_no_match "🐶", response.body
  end

  test "an unknown tab falls back to the class ranking" do
    login_as @s1

    get rankings_path(tab: "bogus")

    assert_response :success
    assert_select "nav a", text: "우리 반"
  end

  private
end
