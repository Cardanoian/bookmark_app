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

  # P2.7 — counts 에 담긴 user_id 가 조회에서 빠지면(유저 삭제/스코프 제외) subject 가 nil 인
  # Entry 가 생겨 뷰의 entry.subject.name 에서 크래시한다. nil subject 는 제외되어야 한다.
  test "challenge ranking skips entries whose user is missing without crashing" do
    challenge = Challenge.create!(title: "겨울 챌린지")
    2.times { |i| Report.create!(user: @s1, classroom: @class1, book_title: "챌#{i}", challenge_id: challenge.id) }
    Report.create!(user: @s2, classroom: @class1, book_title: "챌", challenge_id: challenge.id)

    # @s2 의 User 레코드만 제거해 report 를 고아로 만든다 → users[@s2.id] == nil 인 실제 상황 재현.
    # FK 검사는 커밋까지 지연되고(disable_referential_integrity), 테스트 트랜잭션은 롤백되므로 안전.
    ActiveRecord::Base.connection.disable_referential_integrity do
      User.where(id: @s2.id).delete_all
    end

    ranking = RankingBoard.new(@s1).challenge_ranking(challenge)

    assert(ranking.none? { |entry| entry.subject.nil? }, "nil subject 엔트리는 만들어지면 안 된다")
    assert_equal 1, ranking.size
    assert_equal @s1, ranking.first.subject
    assert_equal 2, ranking.first.score
  end

  # P3.1 행동보존 — 학생이 없는 학교/학급도 종전처럼 합계 0(평균 0)으로 포함되어야 한다.
  test "nation ranking includes schools with no students at score 0" do
    empty_school = School.create!(name: "무학생학교")

    ranking = RankingBoard.new(@s1).nation_ranking
    entry = ranking.find { |e| e.subject == empty_school }

    assert_not_nil entry, "학생이 없는 학교도 전국 순위에 포함되어야 한다"
    assert_equal 0, entry.score
  end

  test "school ranking includes an empty classroom at score 0 and avg 0" do
    empty_class = Classroom.create!(school: @school, grade: 6, class_no: 9)

    ranking = RankingBoard.new(@s1).school_ranking
    entry = ranking.find { |e| e.subject == empty_class }

    assert_not_nil entry, "학생이 없는 학급도 학교 순위에 포함되어야 한다"
    assert_equal 0, entry.score
    assert_equal 0, entry.meta[:avg]
  end

  # P3.1 성능 — 그룹 SQL 전환으로 집계 쿼리가 데이터셋 규모(학교/학급/학생 수)에
  # 비례해 증가하지 않음(N+1 회귀 감지). 규모를 키운 전후 쿼리 수가 같아야 한다.
  test "nation_ranking query count does not grow with the number of schools" do
    baseline = count_queries { RankingBoard.new(@s1).nation_ranking }

    10.times do |i|
      s = School.create!(name: "대량학교#{i}")
      c = Classroom.create!(school: s, grade: 6, class_no: i + 1)
      User.create!(school: s, classroom: c, name: "대량학생#{i}", points: 10, password: "password")
    end

    scaled = count_queries { RankingBoard.new(@s1).nation_ranking }

    assert_equal baseline, scaled, "학교 수가 늘어도 쿼리 수가 증가하면 안 된다(N+1 회귀)"
    assert_operator scaled, :<=, 2, "nation_ranking 은 상수 쿼리(로드 + 그룹 SUM)여야 한다"
  end

  test "school_ranking query count does not grow with the number of classrooms" do
    # 매 측정마다 school.classrooms 연관 캐시를 비워(cold) 실제 로드 쿼리를 재현한다.
    # (@user.school 은 @school 과 동일 객체라 캐시가 재사용되면 측정이 왜곡됨.)
    @school.classrooms.reset
    baseline = count_queries { RankingBoard.new(@s1).school_ranking }

    10.times { |i| Classroom.create!(school: @school, grade: 6, class_no: i + 1) }

    @school.classrooms.reset
    scaled = count_queries { RankingBoard.new(@s1).school_ranking }

    assert_equal baseline, scaled, "학급 수가 늘어도 쿼리 수가 증가하면 안 된다(N+1 회귀)"
    assert_operator scaled, :<=, 3, "school_ranking 은 상수 쿼리(학급 로드 + SUM/COUNT 그룹집계)여야 한다"
  end

  test "hall_of_fame query count does not grow with the number of students" do
    line = MonsterSpecies.where(stage: 1).order(:dex_no).first
    @s1.user_monsters.create!(monster_species: line, dex_no: line.dex_no, obtained_at: Time.current)

    baseline = count_queries { RankingBoard.new(@s1).hall_of_fame }

    10.times do |i|
      extra = User.create!(school: @school, classroom: @class1, name: "전당대량#{i}", points: 5, password: "password")
      extra.user_monsters.create!(monster_species: line, dex_no: line.dex_no, obtained_at: Time.current)
    end

    scaled = count_queries { RankingBoard.new(@s1).hall_of_fame }

    assert_equal baseline, scaled, "학생 수가 늘어도 쿼리 수가 증가하면 안 된다(N+1 회귀)"
    assert_operator scaled, :<=, 4, "hall_of_fame 은 상수 쿼리(학생 로드 + 그룹집계 2회)여야 한다"
  end

  private

  # 순수 SQL 쿼리 수를 센다(스키마·트랜잭션·캐시 쿼리 제외). N+1 회귀 감지용.
  def count_queries
    queries = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]
      next if payload[:sql].match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

      queries += 1
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
