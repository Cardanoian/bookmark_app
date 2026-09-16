require "test_helper"
require "rake"
require "csv"

# research:reports_5axis — 연구용 비식별 원자료 추출(2026-09-16 에 걷어낸 교사 엑셀의 대체).
# 파일이 실제로 무엇을 담고 무엇을 빼는지를 고정한다: 직접 식별정보 0, 미제출 초안 제외,
# 같은 학생은 같은 가명 ID, 자유 입력 책 제목이 스프레드시트 수식이 되지 않음.
class ResearchExportTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("research:reports_5axis")
    @out_dir = Rails.root.join("tmp", "research_export_test_#{SecureRandom.hex(4)}")
    @school = School.create!(name: "원자료초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 3)
    @student = User.create!(school: @school, classroom: @classroom, name: "원자료학생", password: "password")
  end

  teardown { FileUtils.rm_rf(@out_dir) }

  def create_report!(attributes)
    Report.create!({ user: @student, classroom: @classroom, book_title: "마당을 나온 암탉",
                     input_mode: :keyboard, body: "본문" }.merge(attributes))
  end

  def rubric(score)
    ReadingDomain::RUBRIC_AXES.index_with { score }
  end

  def run_task
    Rake::Task["research:reports_5axis"].reenable
    ENV["OUT_DIR"] = @out_dir.relative_path_from(Rails.root).to_s
    ENV["CLASSROOM_IDS"] = @classroom.id.to_s
    output = capture_io { Rake::Task["research:reports_5axis"].invoke }.first
    csv_path = Dir[@out_dir.join("*.csv")].sole
    [ output, CSV.parse(File.read(csv_path).delete_prefix("﻿"), headers: true) ]
  ensure
    ENV.delete("OUT_DIR")
    ENV.delete("CLASSROOM_IDS")
  end

  test "제출한 원본 글과 고쳐쓰기를 한 행으로 내보내고 학생 실명은 넣지 않는다" do
    original = create_report!(submitted_at: 2.days.ago, rubric: rubric(3), avg: 3.0, level: "B")
    create_report!(revision_of: original, submitted_at: 1.day.ago, rubric: rubric(4),
                   avg: 4.0, level: "A", improvement: 1.0)

    output, table = run_task

    assert_equal 1, table.size
    row = table.first
    assert_equal "3.0", row["사전_평균"]
    assert_equal "4.0", row["사후_평균"]
    assert_equal "1.0", row["향상도"]
    assert_equal "4", row["사후_내용 이해"]
    assert_match(/\A학생-[0-9A-F]{12}\z/, row["학생 가명 ID"])
    refute_includes File.read(Dir[@out_dir.join("*.csv")].sole), @student.name
    assert_match "행 1", output
  end

  test "미제출 초안은 세지 않고 제외 건수로만 남긴다" do
    create_report!(submitted_at: 1.day.ago, rubric: rubric(3), avg: 3.0, level: "B")
    create_report!(submitted_at: nil, body: "쓰다 만 글")

    output, table = run_task

    assert_equal 1, table.size
    assert_match "제외한 미제출 초안 1", output
  end

  test "같은 학생의 여러 글은 같은 가명 ID 를 받는다" do
    create_report!(submitted_at: 2.days.ago, rubric: rubric(3), avg: 3.0, level: "B")
    create_report!(submitted_at: 1.day.ago, book_title: "우리들의 일그러진 영웅",
                   rubric: rubric(4), avg: 4.0, level: "A")

    _output, table = run_task

    assert_equal 2, table.size
    assert_equal 1, table.map { |row| row["학생 가명 ID"] }.uniq.size
  end

  test "수식처럼 생긴 책 제목은 수식으로 열리지 않게 감싼다" do
    create_report!(submitted_at: 1.day.ago, book_title: '=HYPERLINK("http://evil","눌러보세요")',
                   rubric: rubric(3), avg: 3.0, level: "B")

    _output, table = run_task

    assert_equal %q('=HYPERLINK("http://evil","눌러보세요")), table.first["도서"]
  end

  test "산출 메타에 범위·제외 기준·실행 환경을 남긴다" do
    create_report!(submitted_at: 1.day.ago, rubric: rubric(3), avg: 3.0, level: "B")

    run_task
    meta = File.read(Dir[@out_dir.join("*_산출메타.md")].sole)

    assert_match "학급 #{@classroom.id}", meta
    assert_match "제외한 미제출 초안", meta
    assert_match RUBY_VERSION, meta
    assert_match "커밋하지 말고", meta
  end
end
