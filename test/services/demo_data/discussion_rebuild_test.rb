require "test_helper"

# 이미 적재된 데모 학급의 토론만 현재 시드 정본(찬반 토론)으로 되돌리는 운영 정비(2026-09-19).
# 찬반 토론 도입 전 운영 DB 처럼 옛 자유 질문 토론방·입장 없는 글이 있는 학급을 만들어 두고 검증한다.
class DemoData::DiscussionRebuildTest < ActiveSupport::TestCase
  SEED_FILE = "sample_3_5.yml"

  setup do
    seed_monster_species!
    seed_badges!
    Book.create!(title: "토론 재구성용 책", summary: "검증된 줄거리")
    @school = School.create!(name: "테스트초등학교", neis_code: "9999999", region: "세종특별자치시교육청",
                             active: true, data_source: "manual")
    DemoSeeder.new(io: StringIO.new, only_files: [ SEED_FILE ]).call
    @classroom = Classroom.find_by!(school: @school, grade: 3, class_no: 5)
    @seed = DemoSeeder.new(io: StringIO.new).seed_data_for(SEED_FILE)

    # 찬반 토론 도입 전 운영 상태: 옛 자유 질문 토론방과 입장 없는 글, 그 글에 붙은 좋아요.
    Topic.where(classroom: @classroom).find_each(&:destroy!)
    students = @classroom.users.where(role: :student).order(:id).to_a
    @old_topic = Topic.create!(classroom: @classroom, title: "가장 좋아하는 등장인물은?")
    old_post = @old_topic.forum_posts.create!(user: students.first, text: "옛 토론 글이에요.")
    ForumPostLike.create!(forum_post: old_post, user: students.second)
    @reports_before = Report.where(classroom: @classroom).count
  end

  test "rebuild requires the demo deployment flag and exact confirmation" do
    error = assert_raises(DemoData::DiscussionRebuild::SafetyError) { build(confirmation: DemoData::DiscussionRebuild::CONFIRMATION).call! }
    assert_includes error.message, "DEMO_DEPLOYMENT=1"

    with_demo_deployment do
      error = assert_raises(DemoData::DiscussionRebuild::SafetyError) { build(confirmation: "wrong").call! }
      assert_includes error.message, "CONFIRM="
    end
    assert Topic.exists?(@old_topic.id)
  end

  test "rebuild refuses when the student roster differs from the seed" do
    User.create!(school: @school, classroom: @classroom, name: "시드에없는학생", password: "password")

    with_demo_deployment do
      assert_raises(DemoData::DiscussionRebuild::SafetyError) { build(confirmation: DemoData::DiscussionRebuild::CONFIRMATION).call! }
    end
    assert Topic.exists?(@old_topic.id)
  end

  test "preview reports the old discussions without changing data" do
    row = build.preview.sole

    assert_equal SEED_FILE, row[:file]
    assert row[:found]
    assert_equal 1, row[:topics]
    assert_equal 0, row[:debate_topics]
    assert_not row[:stances_match]
    assert Topic.exists?(@old_topic.id)
  end

  test "rebuild replaces only the discussions with the seeded debate topics and stances" do
    result = with_demo_deployment { build(confirmation: DemoData::DiscussionRebuild::CONFIRMATION).call! }

    row = result[:after].sole
    assert row[:topics_match]
    assert row[:all_debate]
    assert row[:stances_match]
    assert_equal row[:expected_posts], row[:posts]
    assert_nil result[:backup]
    assert_not Topic.exists?(@old_topic.id)

    topics = Topic.where(classroom: @classroom)
    assert_equal @seed.fetch("topics").map { |topic| topic.fetch("title") }.sort, topics.pluck(:title).sort
    assert_empty ForumPost.where(topic: topics, stance: nil)
    # 토론 밖의 활동은 그대로다.
    assert_equal @reports_before, Report.where(classroom: @classroom).count
  end

  test "only debate seed classrooms are targets" do
    files = DemoData::DiscussionRebuild.new(io: StringIO.new).send(:targets).map { |target| target[:filename] }

    assert_includes files, "sample_3_1.yml"
    assert_includes files, "noeul_3_1.yml"
    assert_not_includes files, "danbi_5_3.yml"
  end

  private

  def build(confirmation: nil)
    DemoData::DiscussionRebuild.new(io: StringIO.new, confirmation:, backup_database: false, only_files: [ SEED_FILE ])
  end

  def with_demo_deployment
    previous = ENV["DEMO_DEPLOYMENT"]
    ENV["DEMO_DEPLOYMENT"] = "1"
    yield
  ensure
    ENV["DEMO_DEPLOYMENT"] = previous
  end
end
