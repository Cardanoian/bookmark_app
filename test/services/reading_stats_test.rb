require "test_helper"

class ReadingStatsTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "지표초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "지표학생", password: "password", points: 320)
    @stats = ReadingStats.new(@user)
  end

  def report(attrs = {})
    Report.create!({ user: @user, classroom: @classroom, book_title: "책" }.merge(attrs))
  end

  # 시드된 라인의 unlock_condition(라인 단위 자동 해금 규칙, stage 1 폼에만 있음)을 읽는다.
  def unlock_condition_for(key)
    MonsterSpecies.find_by!(key: key).unlock_condition
  end

  test "points reads user.points" do
    assert_equal 320, @stats.points
  end

  test "reports counts only reviewed reports" do
    report(reviewed: true)
    report(reviewed: true)
    report(reviewed: false)
    assert_equal 2, @stats.reports
  end

  test "distinct_genres counts distinct book categories among reviewed reports" do
    recommended = Book.create!(title: "추천책", category: :recommended)
    classic = Book.create!(title: "고전책", category: :classic)
    report(reviewed: true, book: recommended)
    report(reviewed: true, book: classic)
    report(reviewed: true, book: classic)
    assert_equal 2, @stats.distinct_genres
  end

  test "a_grades and b_or_better count by level among reviewed reports" do
    report(reviewed: true, level: "A")
    report(reviewed: true, level: "A")
    report(reviewed: true, level: "B")
    report(reviewed: true, level: "C")
    report(reviewed: false, level: "A") # 미승인은 제외(승인 전 인플레이션 방지)
    assert_equal 2, @stats.a_grades
    assert_equal 3, @stats.b_or_better
  end

  test "classics counts reviewed reports on classic books" do
    classic = Book.create!(title: "고전", category: :classic)
    recommended = Book.create!(title: "추천", category: :recommended)
    report(reviewed: true, book: classic)
    report(reviewed: true, book: recommended)
    assert_equal 1, @stats.classics
  end

  # classics 는 distinct book — 같은 고전을 여러 번 읽어도 1권으로만 센다(반복 치팅 차단).
  test "classics counts distinct classic books, not repeated reports of the same book" do
    classic = Book.create!(title: "같은고전", category: :classic)
    report(reviewed: true, book: classic)
    report(reviewed: true, book: classic)
    report(reviewed: true, book: classic)
    assert_equal 1, @stats.classics
  end

  test "classics counts each distinct classic once across many reports" do
    3.times { |i| report(reviewed: true, book: Book.create!(title: "고전#{i}", category: :classic)) }
    assert_equal 3, @stats.classics
  end

  # 진화 회귀 게이트: classics 를 distinct book 으로 바꿔도 turtle_2(classics:3)·dragon_2(classics:2)
  # 진화가 서로 다른 고전으로는 도달 가능해야 한다(같은 책 반복으론 불가).
  test "distinct-classics change keeps turtle_2 and dragon_2 evolution reachable with distinct classics" do
    seed_monster_species!
    3.times { |i| report(reviewed: true, book: Book.create!(title: "다른고전#{i}", category: :classic)) }
    stats = ReadingStats.new(@user)
    assert_equal 3, stats.classics
    assert stats.meets?(MonsterSpecies.find_by(key: "turtle_2").evolve_condition.slice("classics"))
    assert stats.meets?(MonsterSpecies.find_by(key: "dragon_2").evolve_condition.slice("classics"))
  end

  test "reading the same classic repeatedly does not reach classics 2 or 3 (regression against cheating)" do
    classic = Book.create!(title: "반복고전", category: :classic)
    3.times { report(reviewed: true, book: classic) }
    stats = ReadingStats.new(@user)
    assert_equal 1, stats.classics
    assert_not stats.meets?("classics" => 2)
    assert_not stats.meets?("classics" => 3)
  end

  # max_daily_reports — 하루에 제출한 서로 다른 책의 승인 독후감 수 중 역대 최댓값.
  test "max_daily_reports takes the max distinct-book count across submission days" do
    day1 = Time.utc(2026, 6, 1, 3) # KST 12:00 06-01
    day2 = Time.utc(2026, 6, 2, 3) # KST 12:00 06-02
    b = ->(n) { Book.create!(title: n, category: :recommended) }
    report(reviewed: true, created_at: day1, book: b.("d1a"))
    report(reviewed: true, created_at: day1, book: b.("d1b")) # 06-01: 서로 다른 책 2권
    report(reviewed: true, created_at: day2, book: b.("d2a")) # 06-02: 1권
    assert_equal 2, @stats.max_daily_reports
  end

  test "max_daily_reports counts the same book submitted twice in a day only once" do
    day = Time.utc(2026, 6, 1, 3)
    same = Book.create!(title: "같은책", category: :recommended)
    other = Book.create!(title: "다른책", category: :recommended)
    report(reviewed: true, created_at: day, book: same)
    report(reviewed: true, created_at: day, book: same) # 같은 책 → 1권
    report(reviewed: true, created_at: day, book: other) # 다른 책 → +1
    assert_equal 2, @stats.max_daily_reports
  end

  test "max_daily_reports groups by Asia/Seoul submission date, not UTC" do
    seoul_before_midnight = Time.utc(2026, 6, 1, 14, 59) # KST 23:59 06-01
    seoul_after_midnight = Time.utc(2026, 6, 1, 15, 0)   # KST 00:00 06-02 (같은 UTC 날짜)
    report(reviewed: true, created_at: seoul_before_midnight, book: Book.create!(title: "밤늦게", category: :recommended))
    report(reviewed: true, created_at: seoul_after_midnight, book: Book.create!(title: "자정직후", category: :recommended))
    # UTC 로 묶으면 같은 날 2권(=2)이지만, Asia/Seoul 로는 서로 다른 날(각 1권)이라 최댓값 1.
    assert_equal 1, @stats.max_daily_reports
  end

  test "max_daily_reports counts title-only reports and deduplicates normalized titles" do
    day = Time.utc(2026, 6, 1, 3)
    report(reviewed: true, created_at: day, book_title: "책제목만", book: nil)
    report(reviewed: true, created_at: day, book_title: "  책제목만  ", book: nil)
    report(reviewed: true, created_at: day, book_title: "Other Book", book: nil)
    report(reviewed: true, created_at: day, book_title: "other book", book: nil)

    assert_equal 2, @stats.max_daily_reports
  end

  test "max_daily_reports recognizes the same book only once across different days" do
    first_day = Time.utc(2026, 6, 1, 3)
    later_day = Time.utc(2026, 6, 2, 3)
    report(reviewed: true, created_at: first_day, book_title: "강아지 똥", book: nil)
    report(reviewed: true, created_at: later_day, book_title: "  강아지 똥  ", book: nil)
    report(reviewed: true, created_at: later_day, book_title: "다른 책", book: nil)

    # 날짜별로만 중복 제거하면 나중 날이 2편이지만, 전체 기간으로는 각 책이 1편씩이다.
    assert_equal 1, @stats.max_daily_reports
  end

  test "max_daily_reports deduplicates linked and title-only reports for the same book" do
    first_day = Time.utc(2026, 6, 1, 3)
    later_day = Time.utc(2026, 6, 2, 3)
    book = Book.create!(title: "강아지 똥", category: :recommended)
    report(reviewed: true, created_at: first_day, book: book, book_title: nil)
    report(reviewed: true, created_at: later_day, book: nil, book_title: "강아지 똥")
    report(reviewed: true, created_at: later_day, book: nil, book_title: "다른 책")

    assert_equal 1, @stats.max_daily_reports
  end

  test "max_daily_reports is zero when there are no approved reports" do
    report(reviewed: false, book_title: "미승인", book: nil)
    assert_equal 0, @stats.max_daily_reports
  end

  # 3B — game_plays 원장 기반 지표.
  test "game_plays, distinct_games and game_books aggregate the game_plays ledger" do
    b1 = Book.create!(title: "게임책1", category: :recommended)
    b2 = Book.create!(title: "게임책2", category: :recommended)
    today = Time.current.in_time_zone("Asia/Seoul").to_date
    @user.game_plays.create!(game_type: :quiz, book: b1, played_on: today)
    @user.game_plays.create!(game_type: :book, book: b2, played_on: today)
    @user.game_plays.create!(game_type: :whoami, book_id: nil, played_on: today) # 책 없는 교사 퀴즈
    stats = ReadingStats.new(@user)
    assert_equal 3, stats.game_plays
    assert_equal 3, stats.distinct_games
    assert_equal 2, stats.game_books # 책 연결 2건만
  end

  # 게임 재구성 Phase 1 회귀(계획서 §2·§7, 코드리뷰 반영): classic 은 표면 제거로 정상 플레이로는
  # 더는 기록되지 않는다(과거 기록 보존차 enum 값만 남음) — 그러니 DB 에 classic 을 직접 심어
  # 도달을 흉내내면 회귀를 가린다. Phase 2 에서 sequel 이 4번째 정상 플레이 종류가 됐지만, 여기서는
  # dex 21 임계(distinct_games:3, db/seeds/monsters.yml)가 **일부(3종) 플레이만으로도 충족 가능**함을
  # 검증한다(sequel 4종 도달성은 별도로 games_sequel_test 가 distinct_games==4 로 확인).
  test "normal play with three active game types reaches distinct_games:3 (dex 21) after vocab removal" do
    today = Time.current.in_time_zone("Asia/Seoul").to_date
    %i[quiz whoami book].each do |game_type|
      @user.game_plays.create!(game_type: game_type,
                               book: Book.create!(title: "도달책#{game_type}", category: :recommended),
                               played_on: today)
    end
    stats = ReadingStats.new(@user)
    assert_equal 3, stats.distinct_games, "정상 플레이 3종(quiz·whoami·book)으로 distinct_games 는 3 이다"
    assert stats.meets?("distinct_games" => 3), "dex 21 의 distinct_games:3 요구가 3종 플레이만으로 충족 가능해야 한다"
  end

  # 게임 재구성 Phase 5 도달성 확정(§7·§8): 게이트 도입 후 로스터는 quiz·whoami(콘텐츠 게이트)·
  # book·sequel(항상 가능) 4종이다. 활성 4종을 모두 플레이하면 distinct_games==4 이고, game_plays·
  # distinct_games 게임 게이트 몬스터(dex7·dex21·dex23)가 정상 플레이로 전부 도달한다.
  test "playing all four active game types reaches distinct_games==4 and satisfies dex7/dex21/dex23 game gates" do
    seed_monster_species!
    today = Time.current.in_time_zone("Asia/Seoul").to_date
    3.times do |i|
      book = Book.create!(title: "가용책#{i}", category: :recommended)
      %i[quiz whoami book sequel].each do |game_type|
        @user.game_plays.create!(game_type: game_type, book: book, played_on: today)
      end
    end
    stats = ReadingStats.new(@user)
    assert_equal 4, stats.distinct_games
    assert_operator stats.game_plays, :>=, 12
    assert stats.meets?(unlock_condition_for("dokkaebi_1")), "dex23(distinct_games:2) 도달"
    assert stats.meets?(unlock_condition_for("robot_1")),    "dex7(game_plays:8·distinct_games:3) 도달"
    assert stats.meets?(unlock_condition_for("unicorn_1")),  "dex21(game_plays:12·distinct_games:3) 도달"
  end

  # 무명 책만 읽는 학생 바닥(§7): quiz·whoami 는 콘텐츠 게이트로 막히고 항상 가능한 book·sequel 2종만
  # 남는다. 이 바닥에서 dex23(distinct_games:2)은 항상 도달하지만, dex7·dex21(distinct_games:3)은
  # 미도달이어야 한다. game_plays 를 12로 충분히 채워 **미도달의 원인이 오직 distinct_games 게이트**임을
  # 고정한다(도달의 관문이 game_plays 총량이 아니라 서로 다른 게임 종류 수임을 확정).
  test "unknown-book floor (book+sequel only) reaches dex23 but not dex7/dex21 (distinct_games is the gate)" do
    seed_monster_species!
    today = Time.current.in_time_zone("Asia/Seoul").to_date
    6.times do |i|
      book = Book.create!(title: "무명책#{i}", category: :recommended)
      %i[book sequel].each do |game_type|
        @user.game_plays.create!(game_type: game_type, book: book, played_on: today)
      end
    end
    stats = ReadingStats.new(@user)
    assert_equal 2, stats.distinct_games
    assert_operator stats.game_plays, :>=, 12 # game_plays 는 충분 — 미도달은 오직 distinct_games 때문
    assert stats.meets?(unlock_condition_for("dokkaebi_1")),    "dex23(distinct_games:2)은 바닥에서 항상 도달"
    assert_not stats.meets?(unlock_condition_for("robot_1")),    "dex7 은 distinct_games:3 미충족으로 미도달"
    assert_not stats.meets?(unlock_condition_for("unicorn_1")),  "dex21 은 distinct_games:3 미충족으로 미도달"
  end

  test "revisions counts reviewed reports with positive improvement" do
    report(reviewed: true, improvement: 1.5)
    report(reviewed: true, improvement: 0.0)
    report(reviewed: true, improvement: nil)
    report(reviewed: false, improvement: 2.0) # 미승인은 제외
    assert_equal 1, @stats.revisions
  end

  # [PR2 전환] missions 는 완료 participation(completed_at) 을 센다(reports.mission_id 아님).
  test "missions counts completed participations; challenges count legacy report links" do
    completed = Mission.create!(classroom: @classroom, title: "완료미션", start_date: Date.current, end_date: Date.current + 7)
    MissionParticipation.create!(mission: completed, user: @user, completed_at: Time.current)
    # 미완료 참여는 세지 않는다.
    pending = Mission.create!(classroom: @classroom, title: "진행미션", start_date: Date.current, end_date: Date.current + 7)
    MissionParticipation.create!(mission: pending, user: @user)

    challenge = Challenge.create!(title: "챌린지")
    report(challenge_id: challenge.id)

    assert_equal 1, @stats.missions
    assert_equal 1, @stats.challenges
  end

  # 참여 원장만 있고 독후감 연결이 없어도 참여 챌린지로 센다(dex 15·18 해금 조건이 안 걸리던 원인).
  test "challenges counts participations without any linked report" do
    challenge = Challenge.create!(title: "참여만 한 챌린지")
    ChallengeParticipation.create!(challenge: challenge, user: @user, joined_at: Time.current)

    assert_equal 1, @stats.challenges
  end

  # 같은 챌린지가 참여 원장과 레거시 독후감 연결 양쪽에 있어도 1 로 센다(합집합).
  test "challenges de-duplicates a challenge recorded in both paths" do
    both = Challenge.create!(title: "양쪽 기록 챌린지")
    ChallengeParticipation.create!(challenge: both, user: @user, joined_at: Time.current)
    report(challenge_id: both.id)
    legacy_only = Challenge.create!(title: "레거시 연결만 있는 챌린지")
    report(challenge_id: legacy_only.id)

    assert_equal 2, @stats.challenges
  end

  test "cheers_received sums cheers_count" do
    report(cheers_count: 3)
    report(cheers_count: 4)
    assert_equal 7, @stats.cheers_received
  end

  test "streak_days computes longest consecutive submission run" do
    base = Date.new(2026, 6, 1)
    [ 0, 1, 2, 4, 5 ].each do |offset|
      report(created_at: base + offset)
    end
    assert_equal 3, @stats.streak_days
  end

  test "streak_days is zero with no reports" do
    assert_equal 0, @stats.streak_days
  end

  test "quizzes counts the user's quiz_attempts (P5.6 wired)" do
    assert_equal 0, @stats.quizzes
    teacher = User.create!(school: @school, classroom: @classroom, name: "지표교사", password: "password", role: :teacher)
    quiz = Quiz.create!(title: "지표 퀴즈", created_by: teacher, scope: :global)
    quiz.quiz_attempts.create!(user: @user, score: 2, answers: {}, played_at: Time.current)
    quiz.quiz_attempts.create!(user: @user, score: 3, answers: {}, played_at: Time.current)
    assert_equal 2, ReadingStats.new(@user).quizzes
  end

  test "topic_posts counts the user's forum posts (P5.4 wired)" do
    assert_equal 0, @stats.topic_posts
    topic = Topic.create!(scope: :classroom, classroom: @classroom, title: "토론 주제")
    topic.forum_posts.create!(user: @user, text: "첫 글")
    topic.forum_posts.create!(user: @user, text: "둘째 글")
    assert_equal 2, ReadingStats.new(@user).topic_posts
  end

  test "dex_count counts distinct owned dex lines" do
    s1 = MonsterSpecies.create!(key: "rs_pup_1", stage: 1, dex_no: 1)
    s5 = MonsterSpecies.create!(key: "rs_cat_1", stage: 1, dex_no: 5)
    @user.user_monsters.create!(monster_species: s1, dex_no: 1, obtained_at: Time.current)
    @user.user_monsters.create!(monster_species: s5, dex_no: 5, obtained_at: Time.current)
    assert_equal 2, @stats.dex_count
  end

  test "badge? reflects user badge ownership" do
    badge = Badge.create!(key: "first", name: "첫 독후감")
    assert_not @stats.badge?("first")
    @user.user_badges.create!(badge: badge, earned_at: Time.current)
    assert ReadingStats.new(@user).badge?("first")
  end

  test "meets? ANDs numeric keys with >= and requires all" do
    report(reviewed: true)
    report(reviewed: true)
    report(reviewed: true)
    # points 320 >= 100, reports 3 >= 3
    assert @stats.meets?("points" => 100, "reports" => 3)
    assert_not @stats.meets?("points" => 100, "reports" => 4)
    assert_not @stats.meets?("points" => 500, "reports" => 3)
  end

  test "meets? handles badge presence key" do
    badge = Badge.create!(key: "reviser", name: "고쳐쓰기")
    assert_not @stats.meets?("badge" => "reviser")
    @user.user_badges.create!(badge: badge, earned_at: Time.current)
    assert ReadingStats.new(@user).meets?("badge" => "reviser")
  end

  test "meets? is false for blank condition" do
    assert_not @stats.meets?(nil)
    assert_not @stats.meets?({})
  end

  # P1.5 — evolve_condition 은 관리자 자유 편집 JSON. 화이트리스트 밖(오타) 키가 public_send 에서
  # NoMethodError 를 내면 학생 도감이 500 난다. 미충족(false)으로 처리하고 절대 raise 하지 않는다.
  test "meets? treats an unknown key as unmet and never raises" do
    report(reviewed: true)
    report(reviewed: true)
    report(reviewed: true)

    assert_nothing_raised do
      # "reprots" 는 "reports" 오타. 조건이 참이면 안 되고 예외도 없어야 한다.
      assert_not @stats.meets?("reprots" => 3)
    end
  end

  test "meets? with a mix of valid and unknown keys is unmet (AND fails on the unknown key)" do
    report(reviewed: true)
    report(reviewed: true)
    report(reviewed: true)
    # points 320 >= 100 은 참이지만, 알 수 없는 키가 하나라도 있으면 전체가 미충족.
    assert_not @stats.meets?("points" => 100, "bogus_metric" => 1)
  end

  test "meets? still evaluates whitelisted symbol and string keys correctly" do
    report(reviewed: true)
    report(reviewed: true)
    report(reviewed: true)
    assert @stats.meets?(points: 100, reports: 3)
    assert @stats.meets?("points" => 100, "reports" => 3)
  end

  # P2.2 — 지표 메모이제이션은 값을 바꾸지 않고 재계산만 없앤다.
  test "memoization preserves every numeric stat value and to_h" do
    classic = Book.create!(title: "고전", category: :classic)
    report(reviewed: true, level: "A", improvement: 2.0, book: classic)
    report(reviewed: true, level: "B")
    stats = ReadingStats.new(@user)

    # 메모이즈 전(첫 호출)과 후(둘째 호출)의 값이 동일해야 한다.
    before = stats.to_h
    after = stats.to_h
    assert_equal before, after
    # 신선 인스턴스가 계산한 참조값과도 일치(메모이즈가 값을 왜곡하지 않음).
    assert_equal ReadingStats.new(@user).to_h, before
    assert_equal 320, before[:points]
    assert_equal 2, before[:reports]
    assert_equal 1, before[:a_grades]
    assert_equal 2, before[:b_or_better]
    assert_equal 1, before[:classics]
    assert_equal 1, before[:revisions]
  end

  test "each stat method issues no query on a repeated call (memoized)" do
    report(reviewed: true)
    stats = ReadingStats.new(@user)
    ReadingStats::NUMERIC_KEYS.each do |key|
      stats.public_send(key) # 메모 워밍(첫 호출에서 1회 쿼리)
      assert_no_queries do
        assert_not_nil stats.public_send(key), "#{key} 재호출은 메모값을 쿼리 없이 반환해야 한다"
      end
    end
  end
end
