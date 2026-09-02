require "test_helper"

class ReportPolicyTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "정책초등학교")

    @classroom1 = Classroom.create!(school: @school, grade: 3, class_no: 1)
    @classroom2 = Classroom.create!(school: @school, grade: 3, class_no: 2)

    @teacher1 = User.create!(school: @school, classroom: @classroom1, name: "교사1", role: :teacher, password: "password")
    @classroom1.update!(teacher: @teacher1)
    @teacher2 = User.create!(school: @school, classroom: @classroom2, name: "교사2", role: :teacher, password: "password")
    @classroom2.update!(teacher: @teacher2)

    @student1 = User.create!(school: @school, classroom: @classroom1, name: "학생1", password: "password")
    @student2 = User.create!(school: @school, classroom: @classroom2, name: "학생2", password: "password")

    @report1 = Report.create!(user: @student1, classroom: @classroom1, book_title: "1반 독후감")
    @report2 = Report.create!(user: @student2, classroom: @classroom2, book_title: "2반 독후감")
  end

  test "teacher scope resolves only own-classroom reports" do
    resolved = scope_for(@teacher1)
    assert_includes resolved, @report1
    assert_not_includes resolved, @report2
  end

  test "cross-classroom teacher is blocked from other reports" do
    resolved = scope_for(@teacher2)
    assert_includes resolved, @report2
    assert_not_includes resolved, @report1
  end

  test "student scope resolves only own reports" do
    resolved = scope_for(@student1)
    assert_includes resolved, @report1
    assert_not_includes resolved, @report2
  end

  test "school_admin scope resolves all reports within the school" do
    admin = User.create!(school: @school, name: "교무", role: :school_admin, password: "password")
    resolved = scope_for(admin)
    assert_includes resolved, @report1
    assert_includes resolved, @report2
  end

  test "superadmin scope resolves every report" do
    admin = User.create!(name: "총괄", role: :superadmin, password: "password")
    resolved = scope_for(admin)
    assert_includes resolved, @report1
    assert_includes resolved, @report2
  end

  test "show? allows the author but not other students" do
    assert ReportPolicy.new(@student1, @report1).show?
    assert_not ReportPolicy.new(@student2, @report1).show?
  end

  test "show? allows the owning teacher but not another teacher" do
    assert ReportPolicy.new(@teacher1, @report1).show?
    assert_not ReportPolicy.new(@teacher2, @report1).show?
  end

  test "update? allows the author and the owning teacher only" do
    assert ReportPolicy.new(@student1, @report1).update?
    assert ReportPolicy.new(@teacher1, @report1).update?
    assert_not ReportPolicy.new(@student2, @report1).update?
    assert_not ReportPolicy.new(@teacher2, @report1).update?
  end

  test "destroy? allows only the student author" do
    assert ReportPolicy.new(@student1, @report1).destroy?
    assert_not ReportPolicy.new(@student2, @report1).destroy?
    assert_not ReportPolicy.new(@teacher1, @report1).destroy?
  end

  # 공유 게이트 4상태. 게시판은 학급을 넘어 열람되므로 검토를 거치지 않은 글은 올라갈 수 없다.
  test "share? blocks an unsubmitted draft even for the author" do
    assert @report1.draft?, "전제: setup 의 report1 은 미제출 초안이다"
    assert_not ReportPolicy.new(@student1, @report1).share?
    assert_not ReportPolicy.new(@teacher1, @report1).share?
  end

  test "share? blocks a submitted but unreviewed report" do
    @report1.update!(submitted_at: Time.current)

    assert_not ReportPolicy.new(@student1, @report1).share?
    assert_not ReportPolicy.new(@teacher1, @report1).share?
  end

  test "share? allows the author and owning teacher once reviewed" do
    @report1.update!(submitted_at: Time.current, reviewed: true, reviewed_at: Time.current)

    assert ReportPolicy.new(@student1, @report1).share?
    assert ReportPolicy.new(@teacher1, @report1).share?
    assert_not ReportPolicy.new(@student2, @report1).share?
    assert_not ReportPolicy.new(@teacher2, @report1).share?
  end

  # fail-safe: 승인이 풀린 공유 글이라도 '공유 취소'는 가능해야 한다. 막으면 미검토 본문이
  # 게시판에 박제된다(정상 흐름에서는 submit_for_review 가 먼저 공유를 걷는다).
  test "share? still allows unsharing when a shared report is no longer reviewed" do
    @report1.update!(submitted_at: Time.current, reviewed: false, shared: true)

    assert ReportPolicy.new(@student1, @report1).share?
  end

  private

  def scope_for(user)
    ReportPolicy::Scope.new(user, Report.all).resolve
  end
end
