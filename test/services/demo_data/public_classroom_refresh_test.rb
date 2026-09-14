require "test_helper"
require Rails.root.join("db/seeds/demo_seeder").to_s

class DemoData::PublicClassroomRefreshTest < ActiveSupport::TestCase
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
    assert_equal 69, preview[:expected_reports]
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
    assert_equal 69, result.dig(:after, :reports)
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

    assert_equal 69, result.dig(:after, :reports)
    assert_equal 0, result.dig(:after, :drafts)
    assert_equal 31, result.dig(:after, :forum_posts)
    assert_equal 10, result.dig(:after, :book_intros)
    assert_equal 10, result.dig(:after, :book_sequels)
    assert_equal 3, Mission.where(classroom: @classroom).count
    assert_equal 95, GamePlay.where(user_id: @students.map(&:id)).count
    assert_equal 10, LibraryLoan.where(school: @school).count
    assert_equal 5, LibraryEvent.where(school: @school).count
    assert_equal 0, ApplicationRecord.connection.execute("PRAGMA foreign_key_check").size
  end

  private

  def build_service(confirmation: nil, demo_seed: -> { }, content_seed: -> { })
    DemoData::PublicClassroomRefresh.new(
      io: StringIO.new,
      confirmation: confirmation,
      backup_database: false,
      demo_seed: demo_seed,
      content_seed: content_seed
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
end
