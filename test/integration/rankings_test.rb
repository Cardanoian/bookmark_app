require "test_helper"

# P4.10 — 랭킹 페이지 렌더링(탭별) + 포디움 노출.
class RankingsTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    @school = School.create!(name: "랭킹뷰초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @s1 = User.create!(school: @school, classroom: @classroom, name: "랭킹일등", points: 300, password: "password")
    @s2 = User.create!(school: @school, classroom: @classroom, name: "랭킹이등", points: 100, password: "password")
    @s1.update!(nickname: "책왕", ranking_opted_in: true)
    @s2.update!(nickname: "독서별", ranking_opted_in: true)
  end

  test "each ranking tab renders successfully" do
    login_as @s1

    %w[class grade school nation challenge hall].each do |tab|
      get rankings_path(tab: tab)
      assert_response :success, "tab=#{tab} 렌더링 실패"
    end
  end

  test "grade tab renders the same-grade individual ranking" do
    login_as @s1

    get rankings_path(tab: "grade")

    assert_response :success
    assert_select "nav a[aria-current='page']", text: "학년"
    ranking_text = css_select("[id^='ranking_user_']").map(&:text).join(" ")
    assert_includes ranking_text, "책왕"
    assert_includes ranking_text, "독서별"
    assert_not_includes ranking_text, "랭킹일등"
    assert_not_includes ranking_text, "랭킹이등"
  end

  # 시즌 플래그 on 이면 랭킹 행(_ranking_row — Pointable 브로드캐스트와 공유하는 파셜)이
  # 평생 경험치가 아니라 현재 학년도 시즌 경험치를 표시한다.
  test "with seasons on the ranking row shows season experience not lifetime" do
    AppSetting.set("feature_flags", { "ranking_seasons" => true })
    @s1.update!(experience: 7_777) # 평생 경험치(표시되면 안 됨)
    SeasonScore.create!(user: @s1, academic_year: Classroom.current_academic_year, experience_earned: 42)
    login_as @s1

    get rankings_path(tab: "class")

    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(@s1, :ranking)} .badge-yellow", text: "42XP"
    assert_no_match "7777XP", response.body
  end

  test "class tab shows the podium and classroom members" do
    login_as @s1

    get rankings_path(tab: "class")

    assert_response :success
    assert_match "책왕", response.body
    assert_match "독서별", response.body
    assert_select "svg use[href$='#medal-gold']", count: 1
    assert_match "300XP", response.body
  end

  test "class ranking renders each student's active monster image" do
    species = MonsterSpecies.find_by!(key: "pup_1")
    # 이미 확립된 대표 몬스터(발견 연출 대상 아님) — celebrated_at 을 채워 발견 모달 드레인을 배제.
    monster = @s1.user_monsters.create!(monster_species: species, celebrated_at: Time.current)
    @s1.update!(active_monster: monster)
    login_as @s1

    get rankings_path(tab: "class")

    assert_response :success
    images = css_select("img[alt='#{species.name}']")
    assert_equal 2, images.size, "대표 몬스터가 포디움과 랭킹 행에 각각 이미지로 표시되어야 한다"
    images.each do |image|
      assert_match %r{/(?:assets|images)/monsters/pup_1(?:-[^/.]+)?\.webp}, image["src"]
    end
    assert_select "svg use[href$='#mystery']", count: 0
  end

  test "an unknown tab falls back to the class ranking" do
    login_as @s1

    get rankings_path(tab: "bogus")

    assert_response :success
    assert_select "nav a", text: "우리 반"
  end

  private
end
