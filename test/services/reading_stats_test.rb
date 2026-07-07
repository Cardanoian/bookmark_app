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
end
