require "test_helper"

# 교사 학생별 통계 배치 집계(Teacher::StudentStatsQuery). 지표 정확성 + 5축 SQL 집계가
# Report#final_rubric_scores(교사 조정 우선) 와 일치하는지 + 학생 수와 무관한 상수 쿼리를 검증한다.
class Teacher::StudentStatsQueryTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "통계학교")
    @classroom = Classroom.create!(school: @school, grade: 4, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "통계담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = create_student("통계학생")
    @book = Book.create!(title: "통계책", category: :recommended)
  end

  test "counts originals, revisions, approvals and pending separately" do
    approved = create_report(reviewed: true, level: "A")
    create_report(reviewed: false)
    Report.create!(user: @student, classroom: @classroom, book: @book, body: "고쳐쓴 글",
                   revision_of: approved, reviewed: false)

    row = row_for(@student)
    assert_equal 2, row.reports, "원본만 센다(고쳐쓰기 제외)"
    assert_equal 1, row.revisions
    assert_equal 1, row.approved
    assert_equal 1, row.pending
    assert_equal 1, row.a_grades
  end

  test "axis averages prefer the teacher adjusted score per axis (final_rubric_scores parity)" do
    report = create_report(reviewed: true, rubric: { content: 2, emotion: 2, life: 2, structure: 2, spelling: 2 },
                           teacher_rubric: { content: 5 })

    row = row_for(@student)
    assert_equal 1, row.scored
    assert_equal report.final_rubric_scores[:content].to_f, row.axis_averages[:content]
    assert_equal 5.0, row.axis_averages[:content], "교사 조정 축은 조정값"
    assert_equal 2.0, row.axis_averages[:emotion], "미조정 축은 AI 원점수"
    assert_equal 2.6, row.avg_score
  end

  test "axis averages ignore unapproved and unscored reports" do
    create_report(reviewed: false, rubric: { content: 5, emotion: 5, life: 5, structure: 5, spelling: 5 })
    create_report(reviewed: true, rubric: nil)

    row = row_for(@student)
    assert_equal 0, row.scored
    assert_equal 0.0, row.avg_score
    assert row.axis_averages.values.all?(&:zero?)
  end

  test "aggregates games, quizzes, missions, challenges and community activity" do
    GamePlay.create!(user: @student, book: @book, game_type: :quiz, played_on: Date.current)
    GamePlay.create!(user: @student, book: @book, game_type: :book, played_on: Date.current)
    GamePlay.create!(user: @student, book: @book, game_type: :quiz, played_on: Date.current - 1)

    quiz = Quiz.create!(title: "퀴즈", book: @book, created_by: @teacher, published: true)
    QuizAttempt.create!(user: @student, quiz: quiz, score: 1, played_at: Time.current)

    mission = Mission.create!(classroom: @classroom, created_by: @teacher, title: "미션", start_date: Date.current, end_date: Date.current + 7)
    MissionParticipation.create!(mission: mission, user: @student, assigned_at: Time.current, completed_at: Time.current)
    other_mission = Mission.create!(classroom: @classroom, created_by: @teacher, title: "미션2", start_date: Date.current, end_date: Date.current + 7)
    MissionParticipation.create!(mission: other_mission, user: @student, assigned_at: Time.current)

    challenge = Challenge.create!(title: "챌린지", scope: :global)
    ChallengeParticipation.create!(challenge: challenge, user: @student, joined_at: Time.current)

    topic = Topic.create!(title: "토론방", scope: :classroom, classroom: @classroom, school: @school)
    ForumPost.create!(topic: topic, user: @student, text: "재미있게 읽었어요")

    row = row_for(@student)
    assert_equal 3, row.game_plays
    assert_equal 2, row.distinct_games
    assert_equal({ "quiz" => 2, "book" => 1 }, row.game_type_counts)
    assert_equal 1, row.quiz_attempts
    assert_equal 2, row.missions_assigned
    assert_equal 1, row.missions_completed
    assert_equal 1, row.challenges_joined
    assert_equal 0, row.challenges_completed
    assert_equal 1, row.forum_posts
  end

  test "last activity takes the later of report submission and game play" do
    create_report(reviewed: true, created_at: 3.days.ago)
    GamePlay.create!(user: @student, book: @book, game_type: :quiz, played_on: Date.current - 1)

    assert_equal Date.current - 1, row_for(@student).last_activity_on
  end

  test "students without activity report zeros and no last activity" do
    row = row_for(@student)
    assert_equal 0, row.reports
    assert_equal 0, row.game_plays
    assert_nil row.last_activity_on
    assert_not row.active?
  end

  test "query count stays constant as the roster grows" do
    5.times { |i| create_student("추가학생#{i}") }
    students = User.where(classroom: @classroom, role: :student).order(:name).to_a
    assert_equal 6, students.size

    one = count_queries { Teacher::StudentStatsQuery.new([ @student ]).rows }
    many = count_queries { Teacher::StudentStatsQuery.new(students).rows }
    assert_equal one, many, "학생 수가 늘어도 쿼리 수는 그대로여야 한다(GROUP BY 집계)"
  end

  test "empty roster runs no aggregate queries" do
    assert_equal 0, count_queries { Teacher::StudentStatsQuery.new([]).rows }
  end

  private

  def create_student(name)
    User.create!(school: @school, classroom: @classroom, name: name, password: "password")
  end

  def create_report(attributes = {})
    Report.create!({ user: @student, classroom: @classroom, book: @book, body: "본문" }.merge(attributes))
  end

  def row_for(student)
    Teacher::StudentStatsQuery.new([ student ]).rows.first
  end

  def count_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) || payload[:cached]
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
