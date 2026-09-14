require "test_helper"
require "tempfile"
require "yaml"
require Rails.root.join("db/seeds/demo_content_seeder").to_s

class DemoContentSeederTest < ActiveSupport::TestCase
  test "featured peer reports never cross the public demo classroom boundary" do
    school = School.create!(name: "데모학교")
    teacher = User.create!(
      school: school,
      name: "데모담임",
      role: :teacher,
      email: "demo-teacher@example.test",
      password: "password"
    )
    classroom = Classroom.create!(school: school, teacher: teacher, grade: 3, class_no: 1)
    featured_student = User.create!(school: school, classroom: classroom, name: "대표학생", password: "password")
    local_peer = User.create!(school: school, classroom: classroom, name: "같은반학생", password: "password")

    other_school = School.create!(name: "다른학교")
    other_classroom = Classroom.create!(school: other_school, grade: 3, class_no: 1)
    outside_peer = User.create!(
      school: other_school,
      classroom: other_classroom,
      name: "다른반학생",
      password: "password"
    )

    local_reports = create_a_reports(local_peer, classroom, averages: [ 4.1, 4.0 ])
    outside_reports = create_a_reports(outside_peer, other_classroom, averages: [ 5.0, 4.9 ])

    Tempfile.create([ "demo_content", ".yml" ]) do |file|
      file.write(YAML.dump(
        "teacher" => { "email" => teacher.email },
        "student" => { "name" => featured_student.name },
        "featured_reports" => {
          "student_pick_count" => 0,
          "peer_pick_count" => 1,
          "cheer_min" => 0,
          "cheer_max" => 0
        }
      ))
      file.flush

      DemoContentSeeder.new(path: file.path, io: StringIO.new).call
    end

    assert BoardPost.exists?(report_id: local_reports.second.id)
    assert_not BoardPost.exists?(report_id: outside_reports.second.id)
  end

  private

  def create_a_reports(user, classroom, averages:)
    averages.map.with_index do |average, index|
      Report.create!(
        user: user,
        classroom: classroom,
        book_title: "검증 도서 #{user.id}-#{index}",
        body: "학급 경계를 검증하기에 충분한 길이의 독후감 본문입니다.",
        submitted_at: Time.current,
        reviewed: true,
        rubric: { content: 5, emotion: 5, life: 5, structure: 5, spelling: 5 },
        avg: average,
        level: "A"
      )
    end
  end
end
