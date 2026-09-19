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
    classroom = Classroom.create!(school: @school, teacher:, academic_year: Classroom.current_academic_year, grade: 3, class_no: 1)
    seed = DemoSeeder.new(io: StringIO.new).seed_data_for("sample_3_1.yml")
    existing = seed.fetch("students").last(2).map do |student|
      User.create!(school: @school, classroom:, name: student.fetch("name"), password: "x123456")
    end
    Report.create!(user: existing.first, classroom:, book_title: "기존 글", body: "기존 학생이 쓴 글입니다.", submitted_at: Time.current)
    seed.fetch("topics").each { |topic| Topic.create!(classroom:, title: topic.fetch("title")) }

    DemoSeeder.new(io: StringIO.new, only_files: [ "sample_3_1.yml" ]).call

    topics = Topic.where(classroom:)
    assert_equal [ "free" ], topics.distinct.pluck(:kind)
    assert ForumPost.where(topic: topics).exists?
    assert_equal [ nil ], ForumPost.where(topic: topics).distinct.pluck(:stance)
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
