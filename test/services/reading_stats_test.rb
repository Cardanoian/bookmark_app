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

  test "max_daily_reports excludes reports without a book and is zero when none qualify" do
    report(reviewed: true, book_title: "책제목만", book: nil)
    assert_equal 0, @stats.max_daily_reports
    report(reviewed: false, book: Book.create!(title: "미승인", category: :recommended))
    assert_equal 0, @stats.max_daily_reports # 미승인은 제외
  end

  # 3B — game_plays 원장 기반 지표.
  test "game_plays, distinct_games and game_books aggregate the game_plays ledger" do
    b1 = Book.create!(title: "게임책1", category: :recommended)
    b2 = Book.create!(title: "게임책2", category: :recommended)
    today = Time.current.in_time_zone("Asia/Seoul").to_date
    @user.game_plays.create!(game_type: :quiz, book: b1, played_on: today)
    @user.game_plays.create!(game_type: :vocab, book: b2, played_on: today)
    @user.game_plays.create!(game_type: :whoami, book_id: nil, played_on: today) # 책 없는 교사 퀴즈
    stats = ReadingStats.new(@user)
    assert_equal 3, stats.game_plays
    assert_equal 3, stats.distinct_games
    assert_equal 2, stats.game_books # 책 연결 2건만
  end

  test "revisions counts reviewed reports with positive improvement" do
    report(reviewed: true, improvement: 1.5)
    report(reviewed: true, improvement: 0.0)
    report(reviewed: true, improvement: nil)
    report(reviewed: false, improvement: 2.0) # 미승인은 제외
    assert_equal 1, @stats.revisions
  end

  test "missions and challenges count distinct ids" do
    mission = Mission.create!(classroom: @classroom, title: "미션")
    challenge = Challenge.create!(title: "챌린지")
    report(mission_id: mission.id)
    report(mission_id: mission.id)
    report(challenge_id: challenge.id)
    assert_equal 1, @stats.missions
    assert_equal 1, @stats.challenges
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
