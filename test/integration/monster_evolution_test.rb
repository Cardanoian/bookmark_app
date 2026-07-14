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
    login_as @student

    post evolve_monster_path(@monster.dex_no)

    assert_equal "pup_2", @monster.reload.monster_species.key
    assert_equal 1, @monster.dex_no, "제자리 진화(같은 라인)"
    assert @monster.evolved_at.present?
    assert_redirected_to monster_path(@monster.dex_no)
  end

  test "evolve is refused and leaves the species unchanged when conditions are unmet" do
    login_as @student

    post evolve_monster_path(@monster.dex_no)

    assert_equal "pup_1", @monster.reload.monster_species.key
    assert_redirected_to monster_path(@monster.dex_no)
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

  private
end
