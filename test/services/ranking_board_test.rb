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
    [ @s1, @s2, @s3, @s4, @sb ].each_with_index do |student, index|
      student.update!(nickname: "순위#{index + 1}", ranking_opted_in: true)
    end
  end

  test "all rankings include students who choose private identity display" do
    @s1.update!(ranking_opted_in: false)

    assert_includes RankingBoard.new(@s2).class_ranking, @s1
    assert_includes RankingBoard.new(@s2).grade_ranking, @s1
    assert_equal "비공개 학생", @s1.ranking_name
    assert_equal 600, RankingBoard.new(@s2).school_ranking.find { |entry| entry.subject == @class1 }.score
  end

  test "class ranking orders classroom students by experience descending" do
    assert_equal [ @s1, @s2, @s3 ], RankingBoard.new(@s1).class_ranking
  end

  test "podium returns the top 3 in order" do
    assert_equal [ @s1, @s2, @s3 ], RankingBoard.new(@s1).podium
  end

  # 랭킹 기준이 소비 가능한 보유 포인트가 아니라 감소하지 않는 누적 경험치임을 보장한다.
  # 1등(경험치 300)이 포인트를 250 소비해 잔액이 꼴찌 이하로 내려가도 순위는 유지되어야 한다.
  test "class ranking keeps ordering by experience even after points are spent" do
    assert @s1.spend_points!(250), "포인트 차감 성공(잔액 300→50)"
    @s1.reload

    assert_operator @s1.points, :<, @s3.points, "이제 1등의 보유 포인트가 3등보다 적다"
    assert_equal [ @s1, @s2, @s3 ], RankingBoard.new(@s1).class_ranking,
                 "포인트 소비와 무관하게 경험치 순위(300>200>100)를 유지해야 한다"
  end

  test "school ranking aggregates classroom experience totals" do
    ranking = RankingBoard.new(@s1).school_ranking

    assert_equal @class1, ranking.first.subject
    assert_equal 600, ranking.first.score
    assert_equal 600, ranking.first.meta[:points]
    assert_equal @class2, ranking.second.subject
    assert_equal 500, ranking.second.score
  end

  test "nation ranking aggregates school experience totals" do
    ranking = RankingBoard.new(@s1).nation_ranking
    totals = ranking.to_h { |entry| [ entry.subject, entry.score ] }

    assert_equal 1100, totals[@school]
    assert_equal 1000, totals[@school_b]
    assert_equal @school, ranking.first.subject
    assert_equal 1100, ranking.first.meta[:points]
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

  # 계획 §2.3 — 6,300교 전량 렌더 방지: 학생 0명 학교는 전국 순위에서 제외한다(종전 "0점 포함" 계약 폐지).
  test "nation ranking excludes schools with no students" do
    empty_school = School.create!(name: "무학생학교")

    ranking = RankingBoard.new(@s1).nation_ranking

    assert_nil ranking.find { |e| e.subject == empty_school },
               "학생이 없는 학교는 전국 순위에서 제외되어야 한다"
    assert_equal 2, ranking.size, "학생 있는 학교(@school, @school_b)만 집계"
  end

  test "nation ranking excludes inactive schools even when they have students" do
    inactive_school = School.create!(name: "비활성학교", active: false, data_source: "sample")
    inactive_class = Classroom.create!(school: inactive_school, grade: 3, class_no: 1)
    User.create!(
      school: inactive_school,
      classroom: inactive_class,
      name: "비활성학생",
      points: 10_000,
      password: "password"
    )

    ranking = RankingBoard.new(@s1).nation_ranking

    assert_not_includes ranking.map(&:subject), inactive_school
    assert_equal [ @school, @school_b ], ranking.map(&:subject)
  end

  # 계획 §2.3 — Top N(100) 상한 + Top100 밖이면 뷰어 본인 학교 순위를 별도 행(self)으로 덧붙인다.
  test "nation ranking caps at 100 and appends the viewer's own school when outside the top 100" do
    100.times do |i|
      s = School.create!(name: "상위교#{i}")
      c = Classroom.create!(school: s, grade: 6, class_no: 1)
      User.create!(
        school: s,
        classroom: c,
        name: "상위학생#{i}",
        nickname: "상위닉네임#{i}",
        ranking_opted_in: true,
        points: 5000 + i,
        password: "password"
      )
    end

    ranking = RankingBoard.new(@s1).nation_ranking

    assert_equal 101, ranking.size, "Top 100 + 본인 학교 1행"
    assert ranking.first(100).none? { |e| e.subject == @school }, "본인 학교는 Top 100 밖"

    own = ranking.last
    assert_equal @school, own.subject, "마지막 행은 뷰어 본인 학교"
    assert own.meta[:self], "본인 학교 행은 self 로 표시"
    assert_operator own.meta[:rank], :>, 100, "본인 학교 실제 순위는 100 초과"
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
    # 상수 쿼리: 시즌 플래그 조회(AppSetting, 인스턴스당 1회 메모이즈) + 그룹 SUM + 필요한 학교 로드.
    assert_operator scaled, :<=, 3, "nation_ranking 은 상수 쿼리(플래그 + 그룹 SUM + 로드)여야 한다"
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

  # --- 랭킹 시즌제(account_linking_seasons_plan §Phase 1) ---

  # 플래그 on 이면 정렬 기준이 평생 experience 가 아니라 현재 학년도 시즌 경험치가 된다.
  # 평생 경험치가 최고인 최고참이 시즌 0 이면 상위를 독점하지 못하고, 신규는 0 에서 출발한다.
  test "class ranking sorts by current-season experience when the flag is on" do
    enable_seasons!
    # @s3 는 평생 경험치 최저(100)지만 이번 시즌에 가장 많이 적립한다.
    @s3.award_points(500)
    @s1.award_points(10)
    # @s2 는 시즌 미적립(0) — LEFT JOIN 으로 0 에서 출발.

    ranking = RankingBoard.new(@s1).class_ranking

    assert_equal [ @s3, @s1, @s2 ], ranking, "시즌 경험치 순(@s3 500 > @s1 10 > @s2 0)"
    assert_equal 500, ranking.first[:season_experience].to_i
    assert_equal 0, ranking.last[:season_experience].to_i, "신규(시즌 미적립) 학생은 0 출발"
  end

  # 시즌 행이 있어도 플래그 off(기본)면 평생 experience 폴백을 유지한다(전환 스위치).
  test "class ranking falls back to lifetime experience when the flag is off" do
    SeasonScore.create!(user: @s3, academic_year: Classroom.current_academic_year, experience_earned: 9_999)

    assert_equal [ @s1, @s2, @s3 ], RankingBoard.new(@s1).class_ranking,
                 "플래그 off 면 시즌 행을 무시하고 평생 경험치 순(300>200>100)"
  end

  test "grade ranking ranks same-grade students across the school by season experience" do
    enable_seasons!
    @s4.award_points(300) # @class2, 같은 학교·같은 학년(5)
    @s2.award_points(100) # @class1
    @sb.award_points(999) # 타 학교 — 제외 대상

    ranking = RankingBoard.new(@s1).grade_ranking

    assert_includes ranking, @s4
    assert_includes ranking, @s2
    assert_not_includes ranking, @sb, "타 학교 학생은 학년 순위에서 제외"
    assert_equal @s4, ranking.first, "시즌 경험치 최고(@s4 300)"
    assert_equal 300, ranking.first[:season_experience].to_i
  end

  test "grade ranking falls back to lifetime experience when the flag is off" do
    # 플래그 미설정(기본 off) — 평생 experience 순(같은 학교 학년5 전원).
    ranking = RankingBoard.new(@s1).grade_ranking

    assert_equal [ @s4, @s1, @s2, @s3 ], ranking, "평생 경험치 순(@s4 500 > @s1 300 > @s2 200 > @s3 100)"
  end

  test "school ranking aggregates season experience when the flag is on" do
    enable_seasons!
    @s1.award_points(40) # @class1
    @s2.award_points(20) # @class1
    @s4.award_points(70) # @class2

    ranking = RankingBoard.new(@s1).school_ranking

    class2_entry = ranking.find { |entry| entry.subject == @class2 }
    class1_entry = ranking.find { |entry| entry.subject == @class1 }
    assert_equal 70, class2_entry.score, "@class2 시즌 합(@s4 70)"
    assert_equal 60, class1_entry.score, "@class1 시즌 합(@s1 40 + @s2 20)"
    assert_equal @class2, ranking.first.subject, "시즌 합 최고 학급이 1위"
  end

  test "nation ranking aggregates season experience when the flag is on" do
    enable_seasons!
    @s1.award_points(40) # @school
    @sb.award_points(90) # @school_b

    ranking = RankingBoard.new(@s1).nation_ranking
    totals = ranking.to_h { |entry| [ entry.subject, entry.score ] }

    assert_equal 40, totals[@school]
    assert_equal 90, totals[@school_b]
    assert_equal @school_b, ranking.first.subject, "시즌 합 최고 학교가 1위"
  end

  private

  def enable_seasons!
    AppSetting.set("feature_flags", { "ranking_seasons" => true })
  end

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
