require "test_helper"
require Rails.root.join("db/seeds/demo_seeder").to_s

# 데모 시더의 토론방 방식(kind)·글 입장(stance) 적재 계약(2026-09-19 찬반 토론).
# 구조화 주제에 kind: debate 를 단 학급은 찬반 토론 + 검수된 입장으로, 레거시 문자열형 학급은
# 자유 의견 + 입장 없음으로 적재되고, 이미 있는 토론방을 재사용하는 경로에서도 실패하지 않아야 한다.
class DemoData::DemoSeederDiscussionTest < ActiveSupport::TestCase
  setup do
    seed_monster_species!
    seed_badges!
    Book.create!(title: "토론 시드용 책", summary: "검증된 줄거리")
    @school = School.create!(name: "테스트초등학교", neis_code: "9999999", region: "세종특별자치시교육청",
                             active: true, data_source: "manual")
  end

  test "a noeul-template classroom seeds debate topics with the reviewed stances" do
    DemoSeeder.new(io: StringIO.new, only_files: [ "sample_3_5.yml" ]).call

    classroom = Classroom.find_by!(school: @school, grade: 3, class_no: 5)
    topics = Topic.where(classroom:)
    assert_equal [ "debate" ], topics.distinct.pluck(:kind)
    posts = ForumPost.where(topic: topics)
    assert posts.exists?
    assert_empty posts.where(stance: nil), "찬반 토론 글은 모두 입장이 있어야 합니다"
  end

  # 활동량을 줄인 학급도 논제마다 찬성·반대가 함께 남고(소수 의견 20% 이상), 같은 글이 두 번 나오지 않는다.
  # 학생별로 앞에서 자르던 때는 3-5(low)가 찬성 3편뿐이고 3-7(balanced)은 한 논제가 비었다.
  test "scaled noeul-template classrooms keep both stances on every debate topic" do
    seeder = DemoSeeder.new(io: StringIO.new)
    %w[sample_3_5.yml sample_3_7.yml].each do |filename|
      data = seeder.seed_data_for(filename)
      posts = data.fetch("students").flat_map { |student| Array(student["forum_posts"]) }
      texts = posts.map { |post| post.fetch("text") }
      assert_equal texts.size, texts.uniq.size, "#{filename}: 같은 글이 한 학급에 두 번 나오면 안 됩니다"

      by_topic = posts.group_by { |post| post.fetch("topic") }
      assert_equal data.fetch("topics").map { |topic| topic.fetch("key") }.sort, by_topic.keys.sort,
                   "#{filename}: 모든 논제에 글이 있어야 합니다"
      by_topic.each do |topic, rows|
        tally = rows.map { |post| post.fetch("stance") }.tally
        minority = tally.values_at("pro", "con").map(&:to_i).min
        assert minority * 5 >= rows.size, "#{filename} #{topic}: 소수 의견이 20% 미만입니다 (#{tally})"
      end
    end
  end

  # 활동량이 high 인 학급(공개 체험 6-1 포함)은 템플릿 글을 그대로 쓴다.
  test "high-activity noeul-template classrooms keep every template post" do
    seeder = DemoSeeder.new(io: StringIO.new)
    template = YAML.safe_load_file(Rails.root.join("db/seeds/demo/noeul_3_1.yml"))
    template_texts = template.fetch("students").flat_map { |student| Array(student["forum_posts"]) }.map { |post| post.fetch("text") }

    %w[sample_3_3.yml byeolha_3_1.yml haon_3_2.yml].each do |filename|
      texts = seeder.seed_data_for(filename).fetch("students").flat_map { |student| Array(student["forum_posts"]) }.map { |post| post.fetch("text") }
      assert_equal template_texts.sort, texts.sort, filename
    end
  end

  test "a legacy string-topic classroom stays free without stances" do
    DemoSeeder.new(io: StringIO.new, only_files: [ "danbi_5_3.yml" ]).call

    classroom = Classroom.find_by!(school: School.find_by!(neis_code: "9999991"), grade: 5, class_no: 3)
    topics = Topic.where(classroom:)
    assert_equal [ "free" ], topics.distinct.pluck(:kind)
    assert_equal [ nil ], ForumPost.where(topic: topics).distinct.pluck(:stance)
  end

  # 증원 경로는 kind 도입 전에 만든 자유 의견 토론방을 재사용한다 — 입장을 싣지 않아 create! 가 실패하지 않는다.
  test "top-up reusing legacy free topics stores posts without stances" do
    teacher = User.create!(school: @school, name: "김지은", role: :teacher, email: "jieun@gbeai.net", password: "x123456")
    classroom = Classroom.create!(school: @school, teacher:, academic_year: Classroom.current_academic_year, grade: 6, class_no: 1)
    seed = DemoSeeder.new(io: StringIO.new).seed_data_for("sample_6_1.yml")
    existing = seed.fetch("students").last(2).map do |student|
      User.create!(school: @school, classroom:, name: student.fetch("name"), password: "x123456")
    end
    Report.create!(user: existing.first, classroom:, book_title: "기존 글", body: "기존 학생이 쓴 글입니다.", submitted_at: Time.current)
    seed.fetch("topics").each { |topic| Topic.create!(classroom:, title: topic.fetch("title")) }
    # 정본 뒷이야기는 제목이 정확히 같은 카탈로그 도서에 연결한다(없으면 시더가 멈춘다).
    seed.fetch("book_sequels").each { |definition| Book.create!(title: definition.fetch("book_title")) }

    DemoSeeder.new(io: StringIO.new, only_files: [ "sample_6_1.yml" ]).call

    topics = Topic.where(classroom:)
    assert_equal [ "free" ], topics.distinct.pluck(:kind)
    assert ForumPost.where(topic: topics).exists?
    assert_equal [ nil ], ForumPost.where(topic: topics).distinct.pluck(:stance)

    # 증원 계약: 이미 있던 학생 명의의 정본 뒷이야기는 만들지 않고, 새 학생의 것만 만든다.
    assert_not BookSequel.where(user: existing).exists?
    new_authors = seed.fetch("book_sequels").map { |definition| definition.fetch("student_name") } - existing.map(&:name)
    assert_equal new_authors.sort, BookSequel.where(classroom:).joins(:user).pluck("users.name").sort
  end

  # 레거시 문자열형 글은 입장이 없으므로, 학급에 있는 찬반 토론방(사용자가 연 것)에는 배정하지 않는다.
  test "legacy posts are never assigned to an existing debate topic" do
    school = School.create!(name: "단비초등학교", neis_code: "9999991", region: "세종특별자치시교육청",
                            active: true, data_source: "manual")
    classroom = Classroom.create!(school:, academic_year: Classroom.current_academic_year, grade: 5, class_no: 3)
    debate = Topic.create!(classroom:, title: "사용자가 연 찬반 토론", kind: :debate)

    assert_nothing_raised do
      DemoSeeder.new(io: StringIO.new, only_files: [ "danbi_5_3.yml" ]).call
    end
    assert_equal 0, debate.forum_posts.count
  end
end
