require "test_helper"

# P4.7 — 진화(조건 충족/미충족), 소유자 인가(비소유자 403), 활성 몬스터 실시간 브로드캐스트.
class MonsterEvolutionTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "진화통합초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "진화통합학생", password: "password")
    @other = User.create!(school: @school, classroom: @classroom, name: "다른진화학생", password: "password")
    @monster = MonsterAcquisition.new(@student).choose_starter!("pup_1")
  end

  def meet_pup_condition!
    @student.update!(points: 100)
    3.times { |i| Report.create!(user: @student, classroom: @classroom, book_title: "책#{i}", reviewed: true) }
  end

  test "evolve advances the species in place when conditions are met" do
    meet_pup_condition!
    @student.update!(points: 130)
    login_as @student

    post evolve_monster_path(@monster.dex_no)

    assert_equal "pup_2", @monster.reload.monster_species.key
    assert_equal 30, @student.reload.points, "현재 단계의 points 조건만큼만 차감"
    assert_equal 1, @monster.dex_no, "제자리 진화(같은 라인)"
    assert @monster.evolved_at.present?
    assert_redirected_to monster_path(@monster.dex_no)
    assert_match "100포인트를 사용해", flash[:notice]
  end

  test "evolve is refused and leaves the species unchanged when conditions are unmet" do
    @student.update!(points: 90)
    login_as @student

    post evolve_monster_path(@monster.dex_no)

    assert_equal "pup_1", @monster.reload.monster_species.key
    assert_equal 90, @student.reload.points, "실패한 진화는 포인트를 차감하지 않음"
    assert_redirected_to monster_path(@monster.dex_no)
  end

  test "detail shows the point cost on the evolution button" do
    meet_pup_condition!
    login_as @student

    get monster_path(@monster.dex_no)

    assert_response :success
    assert_match "100P로 진화하기", response.body
  end

  test "detail centers the monster image" do
    login_as @student

    get monster_path(@monster.dex_no)

    assert_response :success
    assert_select "#monster_detail [data-monster-care-target='sprite'] img.mx-auto", count: 1
    assert_select "#monster_detail img[src*='monsters/pup_1'][src$='.webp']", count: 1
  end

  test "evolve deducts points for a non-active monster too" do
    inactive = MonsterAcquisition.new(@student).discover_monster!("hamster_1")
    meet_pup_condition!
    @student.update!(points: 200)
    login_as @student

    post evolve_monster_path(inactive.dex_no)

    assert_equal "hamster_2", inactive.reload.monster_species.key
    assert_equal "pup_1", @monster.reload.monster_species.key, "대표 몬스터는 바뀌지 않음"
    assert_equal 100, @student.reload.points
  end

  test "a non-owner cannot evolve a line they do not own (403)" do
    login_as @other

    post evolve_monster_path(@monster.dex_no)

    assert_response :forbidden
    assert_equal "pup_1", @monster.reload.monster_species.key
  end

  test "evolving broadcasts the updated active monster to the user stream" do
    meet_pup_condition!
    login_as @student

    assert_turbo_stream_broadcasts [ @student, :active_monster ], count: 1 do
      post evolve_monster_path(@monster.dex_no)
    end
  end

  test "evolving grants the first_evolve badge" do
    meet_pup_condition!
    login_as @student

    post evolve_monster_path(@monster.dex_no)

    assert_includes @student.badges.reload.pluck(:key), "first_evolve"
  end

  # 첨삭 완료(done)됐지만 교사 승인 전(reviewed: false)인 독후감은 진화 조건 '독후감 수'
  # (승인 기준)에 안 잡힌다. 도감 상세가 그 시점 차이를 학생에게 안내하는지 검증.
  test "detail notes AI-reviewed reports awaiting teacher approval when reports is a condition" do
    Report.create!(user: @student, classroom: @classroom, book_title: "대기책", ai_status: :done, reviewed: false)
    login_as @student

    get monster_path(@monster.dex_no)

    assert_response :success
    assert_match "선생님의 승인을 기다리고 있어요", response.body
    assert_match "독후감 1개", response.body
  end

  test "detail hides the approval notice when no reports await teacher approval" do
    Report.create!(user: @student, classroom: @classroom, book_title: "승인책", ai_status: :done, reviewed: true)
    login_as @student

    get monster_path(@monster.dex_no)

    assert_response :success
    assert_no_match "승인을 기다리고 있어요", response.body
  end

  private
end
