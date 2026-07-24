require "test_helper"

# P2-3 몬스터 성장 서사가 상세 화면에 단계별로 공개되는지 검증.
# 도달한 단계까지만 장면을 열고, 완전 성장 시 성장 메시지를 공개하며, 미보유 라인은 티저만 노출한다.
class MonsterStoryTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "서사초등학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "서사학생", password: "password")
  end

  test "owned stage-1 monster reveals scene 1 and locks later scenes and the growth message" do
    MonsterAcquisition.new(@student).choose_starter!("pup_1") # dex 1, stage 1
    login_as @student

    get monster_path(1)
    assert_response :success

    story = MonsterLore.for(1)
    assert_includes response.body, ERB::Util.html_escape(story.scene_for(1).body), "1단계 장면은 공개돼야 한다"
    assert_not_includes response.body, ERB::Util.html_escape(story.scene_for(3).body), "완전형 장면은 잠겨 있어야 한다"
    assert_not_includes response.body, ERB::Util.html_escape(story.growth_message), "완전 성장 전에는 성장 메시지가 숨겨져야 한다"
    assert_includes response.body, "진화하면 이어지는 이야기가 열려요"
  end

  test "fully evolved monster reveals every scene and the growth message" do
    monster = MonsterAcquisition.new(@student).choose_starter!("pup_1")
    monster.update!(monster_species: MonsterSpecies.find_by(key: "pup_3")) # stage 3(완전형)
    login_as @student

    get monster_path(1)
    assert_response :success

    story = MonsterLore.for(1)
    assert_includes response.body, ERB::Util.html_escape(story.scene_for(1).body)
    assert_includes response.body, ERB::Util.html_escape(story.scene_for(3).body)
    assert_includes response.body, ERB::Util.html_escape(story.growth_message)
    assert_not_includes response.body, MonsterLore.completion_finale.heading
    assert_no_match(/>\s*(?:기·승|전|결)\s*</, response.body)
  end

  test "undiscovered monster shows only the locked teaser" do
    login_as @student

    get monster_path(2) # 미보유 라인
    assert_response :success

    story = MonsterLore.for(2)
    assert_includes response.body, "아직 만나지 못한 몬스터"
    assert_not_includes response.body, ERB::Util.html_escape(story.scene_for(1).body)
  end

  test "all final forms unlock the dex completion finale on a monster detail" do
    MonsterSpecies.where(stage: MonsterSpecies::MAX_STAGE).find_each do |species|
      UserMonster.create!(user: @student, monster_species: species)
    end
    login_as @student

    get monster_path(1)
    assert_response :success

    finale = MonsterLore.completion_finale
    assert_includes response.body, finale.heading
    finale.paragraphs.each { |paragraph| assert_includes response.body, ERB::Util.html_escape(paragraph) }
  end
end
