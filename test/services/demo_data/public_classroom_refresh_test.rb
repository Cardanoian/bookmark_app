require "test_helper"
require Rails.root.join("db/seeds/demo_seeder").to_s

class DemoData::PublicClassroomRefreshTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(
      name: "테스트초등학교",
      neis_code: "9999999",
      region: "세종특별자치시교육청",
      active: true,
      data_source: "manual"
    )
    @teacher = User.create!(
      school: @school,
      name: "김지은",
      role: :teacher,
      email: "jieun@gbeai.net",
      password: "changed-password"
    )
    @admin = User.create!(
      school: @school,
      name: "박은수",
      role: :school_admin,
      email: "eunsu@gbeai.net",
      password: "changed-password"
    )
    @librarian = User.create!(
      school: @school,
      name: "최지혜",
      role: :librarian,
      email: "jihye@gbeai.net",
      password: "changed-password"
    )
    @classroom = Classroom.create!(
      school: @school,
      teacher: @teacher,
      academic_year: 2026,
      grade: 3,
      class_no: 1
    )
    @seed_data = DemoSeeder.new(io: StringIO.new).seed_data_for("sample_3_1.yml")
    @students = @seed_data.fetch("students").map do |student_data|
      User.create!(
        school: @school,
        classroom: @classroom,
        name: student_data.fetch("name"),
        nickname: "변경#{student_data.fetch('name')}",
        ranking_opted_in: false,
        points: 999,
        experience: 999,
        password: "changed-password"
      )
    end
    @book = Book.create!(title: "체험 정비용 책", summary: "검증된 줄거리")
  end

  test "preview is read-only and reports the difference from the reviewed seed" do
    create_dirty_activity!
    service = build_service

    preview = service.preview

    assert_equal true, preview[:target_found]
    assert_equal 21, preview[:students]
    assert_equal 102, preview[:expected_reports]
    assert_equal 2, preview[:reports]
    assert_equal 1, preview[:drafts]
    assert Report.exists?(@draft.id)
  end

  test "refresh requires the demo deployment flag and exact confirmation" do
    error = assert_raises(DemoData::PublicClassroomRefresh::SafetyError) do
      build_service(confirmation: DemoData::PublicClassroomRefresh::CONFIRMATION).call!
    end
    assert_includes error.message, "DEMO_DEPLOYMENT=1"

    with_demo_deployment do
      error = assert_raises(DemoData::PublicClassroomRefresh::SafetyError) do
        build_service(confirmation: "wrong").call!
      end
      assert_includes error.message, "CONFIRM="
    end
  end

  test "refresh refuses to delete when the student identity set differs from the seed" do
    outsider = User.create!(
      school: @school,
      classroom: @classroom,
      name: "시드에없는학생",
      password: "password"
    )

    with_demo_deployment do
      assert_raises(DemoData::PublicClassroomRefresh::SafetyError) do
        build_service(confirmation: DemoData::PublicClassroomRefresh::CONFIRMATION).call!
      end
    end

    assert User.exists?(outsider.id)
  end

  test "refresh removes mutable activity and restores the reviewed seed state atomically" do
    create_dirty_activity!
    demo_seed_calls = 0
    content_seed_calls = 0
    service = build_service(
      confirmation: DemoData::PublicClassroomRefresh::CONFIRMATION,
      demo_seed: lambda {
        demo_seed_calls += 1
        seed_reviewed_reports!
      },
      content_seed: -> { content_seed_calls += 1 }
    )

    result = with_demo_deployment { service.call! }

    assert_equal 1, demo_seed_calls
    assert_equal 1, content_seed_calls
    assert_equal 2, result.dig(:before, :reports)
    assert_equal 102, result.dig(:after, :reports)
    assert_equal 0, result.dig(:after, :drafts)
    assert_nil result[:backup]
    assert_not Report.exists?(@draft.id)
    assert_not BookSequel.exists?(@sequel.id)
    assert_not Topic.exists?(@topic.id)
    assert_not Mission.exists?(@mission.id)
    assert_not Quiz.exists?(@quiz.id)
    assert_equal 0, LibraryLoan.where(school: @school).count
    assert_equal 0, LibraryEvent.where(school: @school).count
    assert_equal @seed_data.fetch("students").first.fetch("nickname"), @students.first.reload.nickname
    assert @students.first.authenticate(DemoSeeder::STUDENT_PASSWORD)
    assert @teacher.reload.authenticate("jieun11!")
    assert @admin.reload.authenticate("eunsu11!")
    assert @librarian.reload.authenticate("jihye11!")
  end

  test "refresh rebuilds the complete public classroom with the real reviewed seeders" do
    seed_monster_species!
    seed_badges!
    create_dirty_activity!
    service = DemoData::PublicClassroomRefresh.new(
      io: StringIO.new,
      confirmation: DemoData::PublicClassroomRefresh::CONFIRMATION,
      backup_database: false
    )

    result = with_demo_deployment { service.call! }

    assert_equal 102, result.dig(:after, :reports)
    assert_equal 0, result.dig(:after, :drafts)
    assert_equal 31, result.dig(:after, :forum_posts)
    assert_reviewed_discussions!
    assert_equal 10, result.dig(:after, :book_intros)
    assert_equal 10, result.dig(:after, :book_sequels)
    assert_equal 3, Mission.where(classroom: @classroom).count
    assert_equal 101, GamePlay.where(user_id: @students.map(&:id)).count
    assert_equal 10, LibraryLoan.where(school: @school).count
    assert_equal 5, LibraryEvent.where(school: @school).count
    assert_public_demo_story!(result)
    assert_role_screens_agree!
    assert_equal 0, ApplicationRecord.connection.execute("PRAGMA foreign_key_check").size
  end

  private

  def assert_reviewed_discussions!
    titles_by_key = @seed_data.fetch("topics").to_h { |topic| [ topic.fetch("key"), topic.fetch("title") ] }
    expected = @seed_data.fetch("students").flat_map do |student|
      Array(student["forum_posts"]).map do |post|
        [ titles_by_key.fetch(post.fetch("topic")), post.fetch("stance"), post.fetch("text") ]
      end
    end.sort
    actual = Topic.where(classroom: @classroom).includes(:forum_posts).flat_map do |topic|
      topic.forum_posts.map { |post| [ topic.title, post.stance, post.text ] }
    end.sort

    assert_equal @seed_data.fetch("topics").pluck("title").sort,
                 Topic.where(classroom: @classroom).pluck(:title).sort
    # 공개 체험 논제는 모두 찬반 토론이라, 검수된 입장이 그대로 저장돼 찬성·반대 칸으로 나뉜다.
    assert_equal [ "debate" ], Topic.where(classroom: @classroom).distinct.pluck(:kind)
    assert_equal expected, actual
    assert_equal actual.size, actual.map(&:last).uniq.size, "같은 학급에 똑같은 토론 글이 두 번 보이면 안 됩니다"
    assert actual.none? { |_title, _stance, text| text.match?(/[『』「」“”‘’—…·]/) },
           "토론 글은 학생이 직접 친 글처럼 책 제목 괄호·특수 문장부호를 쓰지 않습니다"
    assert_balanced_stances!
  end

  # 찬반 논제라 한쪽 입장이 8할을 넘으면 토론처럼 보이지 않는다(2026-09-19 사용자 기준).
  def assert_balanced_stances!
    posts = @seed_data.fetch("students").flat_map { |student| Array(student["forum_posts"]) }
    posts.group_by { |post| post.fetch("topic") }.each do |topic, rows|
      stances = rows.map { |post| post.fetch("stance") }
      assert_equal [], stances - %w[pro con], "#{topic}: stance는 pro/con 중 하나여야 합니다"
      minority = stances.tally.values_at("pro", "con").map(&:to_i).min
      assert minority * 5 >= stances.size, "#{topic}: 소수 의견이 20% 미만입니다 (#{stances.tally})"
    end
  end

  def build_service(confirmation: nil, demo_seed: -> { }, content_seed: -> { })
    DemoData::PublicClassroomRefresh.new(
      io: StringIO.new,
      confirmation: confirmation,
      backup_database: false,
      demo_seed: demo_seed,
      content_seed: content_seed,
      validate_story: false
    )
  end

  def with_demo_deployment
    previous = ENV["DEMO_DEPLOYMENT"]
    ENV["DEMO_DEPLOYMENT"] = "1"
    yield
  ensure
    ENV["DEMO_DEPLOYMENT"] = previous
  end

  def create_dirty_activity!
    student = @students.first
    @draft = Report.create!(
      user: student,
      classroom: @classroom,
      book_title: "낙서 초안",
      body: "방문자가 남긴 정리 대상 임시 글입니다."
    )
    Report.create!(
      user: student,
      classroom: @classroom,
      book_title: "추가 글",
      body: "방문자가 제출한 정리 대상 추가 글입니다.",
      submitted_at: Time.current
    )
    @topic = Topic.create!(classroom: @classroom, title: "정리 대상 토론")
    ForumPost.create!(topic: @topic, user: student, text: "정리할 체험 토론 글")
    @sequel = BookSequel.create!(
      user: student,
      classroom: @classroom,
      book: @book,
      body: "방문자가 남긴 정리 대상 뒷이야기입니다."
    )
    @mission = Mission.create!(
      classroom: @classroom,
      created_by: @teacher,
      title: "정리 대상 미션",
      start_date: Date.current,
      end_date: Date.current + 7.days,
      status: :draft
    )
    @quiz = Quiz.create!(
      classroom: @classroom,
      created_by: @teacher,
      title: "정리 대상 퀴즈",
      scope: :classroom
    )
    GamePlay.create!(user: student, game_type: :quiz, book: @book, played_on: Date.current)
    LibraryLoan.create!(school: @school, book_title: "정리 대상 대출", count: 3, source: :csv)
    LibraryEvent.create!(school: @school, title: "정리 대상 행사")
  end

  def seed_reviewed_reports!
    @seed_data.fetch("students").each do |student_data|
      user = @students.find { |student| student.name == student_data.fetch("name") }
      Array(student_data["reports"]).each_with_index do |_report_data, index|
        Report.create!(
          user: user,
          classroom: @classroom,
          book_title: "검수된 책 #{index + 1}",
          body: "검수된 시연용 독후감 본문입니다. 충분한 길이로 작성했습니다.",
          submitted_at: Time.current,
          reviewed: true
        )
      end
    end
  end

  def assert_public_demo_story!(result)
    preview = result.fetch(:after)
    assert_equal true, preview[:story_student_found]
    assert_equal 34, preview[:story_reports]
    assert_equal 1, preview[:story_revisions]
    assert_equal true, preview[:story_revision_growth]
    assert_equal true, preview[:story_feedback_visible]
    assert_equal 1, preview[:featured_reports]
    assert_equal 1, preview[:story_featured_reports]
    assert_equal 1, preview[:story_completed_missions]
    assert_equal true, preview[:story_mission_progress_consistent]
    assert_equal "robot_1", preview[:story_active_monster_key]
    assert_equal true, preview[:story_monster_evolvable]
    assert_equal true, preview[:role_report_counts_match]

    student = @students.find { |user| user.name == "이도현" }.reload
    timeline = StudentGrowthTimeline.new(student)
    assert_equal 34, timeline.approved_report_count
    assert_equal timeline.previous.report, timeline.latest.report.revision_of
    assert_equal "A", timeline.latest.report.level
    assert timeline.changes.values.all?(&:positive?)
    assert_equal timeline.latest.report, BoardPost.joins(:report).find_by!(reports: { user_id: student.id }).report
    assert_equal "robot_1", student.active_monster.species.key
    assert student.active_monster.evolvable?
  end

  def assert_role_screens_agree!
    student = @students.find { |user| user.name == "이도현" }.reload
    login_as student, password: DemoSeeder::STUDENT_PASSWORD
    get growth_path
    assert_response :success
    assert_select ".stat-card", text: /확인받은 독후감\s*34편/
    assert_match "가장 많이 성장", response.body

    delete session_path
    login_as @teacher.reload, password: "jieun11!"
    get teacher_dashboard_path
    assert_response :success
    assert_select ".stat-card", text: /총 독후감\s*102/
    assert_select ".stat-card" do |cards|
      assert_includes cards.map { |card| card.text.squish }, "검토 대기 11"
    end

    delete session_path
    login_as @admin.reload, password: "eunsu11!"
    get school_admin_stats_path
    assert_response :success
    assert_select ".stat-card", text: /학생 수\s*21/
    assert_select ".stat-card", text: /총 독후감\s*102/
  end
end
