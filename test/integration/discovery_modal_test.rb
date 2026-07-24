require "test_helper"

# WS-F 발견 연출 UI(영속 드레인) e2e. 미연출(celebrated_at IS NULL) UserMonster 가 학생의
# 아무 페이지 로드에서 축하 모달로 렌더되고, acknowledge 로 celebrated_at 이 마킹되어
# 재노출되지 않으며(멱등), 교사 승인으로 생긴 발견도 학생 다음 로드에서 확인되는지 검증한다.
# flash/broadcast 가 닿지 못하는 오프라인·교차행위자 발견을 유실 없이 흡수하는 계약이다.
class DiscoveryModalTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "발견연출초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "발견담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "발견학생", password: "password")
  end

  # 학생에게 미연출(또는 이미 연출된) UserMonster 를 직접 만들어 준다.
  def give_monster(key, celebrated: false)
    species = MonsterSpecies.find_by!(key: key)
    @student.user_monsters.create!(
      monster_species: species, dex_no: species.dex_no,
      obtained_at: Time.current, celebrated_at: celebrated ? Time.current : nil
    )
  end

  test "a student with an uncelebrated monster sees the discovery modal on any page load" do
    monster = give_monster("pup_1")
    login_as @student

    get root_path
    assert_response :success
    assert_select "#discovery-modal", 1
    assert_select "#discovery-modal h2", text: monster.species.name
  end

  test "an already celebrated monster is not shown (backfill exclusion)" do
    give_monster("pup_1", celebrated: true)
    login_as @student

    get root_path
    assert_response :success
    assert_select "#discovery-modal", 0
  end

  test "acknowledge marks celebrated_at and the modal does not reappear (idempotent)" do
    give_monster("pup_1")
    login_as @student

    get root_path
    assert_select "#discovery-modal", 1

    assert_difference -> { @student.user_monsters.pending_celebration.count }, -1 do
      post acknowledge_discoveries_path
    end
    assert_response :ok

    get root_path
    assert_select "#discovery-modal", 0
  end

  test "acknowledge scoped by dex_no only marks that line" do
    pup = give_monster("pup_1")
    cat = give_monster("cat_1")
    login_as @student

    post acknowledge_discoveries_path, params: { dex_no: [ pup.dex_no ] }
    assert_response :ok

    assert_equal 1, @student.user_monsters.pending_celebration.count
    assert_not_nil @student.user_monsters.find_by(dex_no: pup.dex_no).celebrated_at
    assert_nil @student.user_monsters.find_by(dex_no: cat.dex_no).celebrated_at
  end

  test "multiple uncelebrated monsters are queued in the modal" do
    pup = give_monster("pup_1")
    cat = give_monster("cat_1")
    login_as @student

    get root_path
    assert_select "#discovery-modal [data-discovery-target='card']", 2
    assert_select "#discovery-modal h2", text: pup.species.name
    assert_select "#discovery-modal h2", text: cat.species.name
  end

  test "a teacher approval discovers a monster that the student sees on the next load" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "책", ai_status: :done)
    login_as @teacher
    post approve_teacher_review_path(report)
    assert @student.user_monsters.pending_celebration.exists?, "승인으로 미연출 몬스터가 생긴다"

    login_as @student
    get root_path
    assert_response :success
    assert_select "#discovery-modal", 1
  end

  test "non-student users never render the discovery modal" do
    login_as @teacher
    get root_path
    assert_response :success
    assert_select "#discovery-modal", 0
  end

  test "acknowledge is student-gated" do
    login_as @teacher
    post acknowledge_discoveries_path
    assert_response :forbidden
  end
end
