require "test_helper"

# P4.10 — 랭킹 집계 정확성(학급/학교/전국/포디움/명예의 전당).
class RankingBoardTest < ActiveSupport::TestCase
  setup do
    seed_monster_species!
    @school = School.create!(name: "랭킹A초등학교")
    @school_b = School.create!(name: "랭킹B초등학교")
    @class1 = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @class2 = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @class_b = Classroom.create!(school: @school_b, grade: 5, class_no: 1)

    @s1 = User.create!(school: @school, classroom: @class1, name: "일등", points: 300, password: "password")
    @s2 = User.create!(school: @school, classroom: @class1, name: "이등", points: 200, password: "password")
    @s3 = User.create!(school: @school, classroom: @class1, name: "삼등", points: 100, password: "password")
    @s4 = User.create!(school: @school, classroom: @class2, name: "다른반", points: 500, password: "password")
    @sb = User.create!(school: @school_b, classroom: @class_b, name: "타교", points: 1000, password: "password")
  end

  test "class ranking orders classroom students by points descending" do
    assert_equal [ @s1, @s2, @s3 ], RankingBoard.new(@s1).class_ranking
  end

  test "podium returns the top 3 in order" do
    assert_equal [ @s1, @s2, @s3 ], RankingBoard.new(@s1).podium
  end

  test "school ranking aggregates classroom point totals" do
    ranking = RankingBoard.new(@s1).school_ranking

    assert_equal @class1, ranking.first.subject
    assert_equal 600, ranking.first.score
    assert_equal @class2, ranking.second.subject
    assert_equal 500, ranking.second.score
  end

  test "nation ranking aggregates school point totals" do
    ranking = RankingBoard.new(@s1).nation_ranking
    totals = ranking.to_h { |entry| [ entry.subject, entry.score ] }

    assert_equal 1100, totals[@school]
    assert_equal 1000, totals[@school_b]
    assert_equal @school, ranking.first.subject
  end

  test "hall of fame reflects dex completion and 완전형(stage 3) count" do
    MonsterSpecies.where(stage: 1).order(:dex_no).limit(3).each do |species|
      @s1.user_monsters.create!(monster_species: species, dex_no: species.dex_no, obtained_at: Time.current)
    end
    promoted = @s1.user_monsters.first
    stage3 = MonsterSpecies.find_by(dex_no: promoted.dex_no, stage: MonsterSpecies::MAX_STAGE)
    promoted.update!(monster_species: stage3)

    only_line = MonsterSpecies.where(stage: 1).order(:dex_no).first
    @s2.user_monsters.create!(monster_species: only_line, dex_no: only_line.dex_no, obtained_at: Time.current)

    hall = RankingBoard.new(@s1).hall_of_fame

    top = hall.first
    assert_equal @s1, top.subject
    assert_equal 3, top.meta[:dex]
    assert_equal 1, top.meta[:complete]
    assert_equal 4, top.score, "성장 신호 = 도감(3) + 완전형(1)"

    runner_up = hall.find { |entry| entry.subject == @s2 }
    assert_equal 1, runner_up.meta[:dex]
    assert_equal 0, runner_up.meta[:complete]

    assert_nil hall.find { |entry| entry.subject == @s3 }, "몬스터 미보유 학생은 전당에서 제외"
  end

  test "challenge ranking counts participation reports" do
    challenge = Challenge.create!(title: "겨울 챌린지")
    2.times { |i| Report.create!(user: @s1, classroom: @class1, book_title: "챌#{i}", challenge_id: challenge.id) }
    Report.create!(user: @s2, classroom: @class1, book_title: "챌", challenge_id: challenge.id)

    ranking = RankingBoard.new(@s1).challenge_ranking(challenge)

    assert_equal @s1, ranking.first.subject
    assert_equal 2, ranking.first.score
    assert_equal @s2, ranking.second.subject
    assert_equal 1, ranking.second.score
  end
end
