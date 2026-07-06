require "test_helper"

# P2.8 — 인가 경계 회귀 세트.
# 5역할 × {Report, Classroom} 스코프 해석을 매트릭스로 검증한다.
# 각 역할은 허용된 레코드만 보고, 경계 밖 레코드는 제외되어야 한다.
class AuthorizationMatrixTest < ActiveSupport::TestCase
  setup do
    @school_a = School.create!(name: "매트릭스A초")
    @school_b = School.create!(name: "매트릭스B초")

    @class_a1 = Classroom.create!(school: @school_a, grade: 3, class_no: 1)
    @class_a2 = Classroom.create!(school: @school_a, grade: 3, class_no: 2)
    @class_b1 = Classroom.create!(school: @school_b, grade: 3, class_no: 1)

    @teacher_a1 = User.create!(school: @school_a, classroom: @class_a1, name: "A1교사", role: :teacher, password: "password")
    @class_a1.update!(teacher: @teacher_a1)
    @teacher_a2 = User.create!(school: @school_a, classroom: @class_a2, name: "A2교사", role: :teacher, password: "password")
    @class_a2.update!(teacher: @teacher_a2)

    @student_a1 = User.create!(school: @school_a, classroom: @class_a1, name: "A1학생", password: "password")
    @student_a2 = User.create!(school: @school_a, classroom: @class_a2, name: "A2학생", password: "password")
    @student_b1 = User.create!(school: @school_b, classroom: @class_b1, name: "B1학생", password: "password")

    @school_admin_a = User.create!(school: @school_a, name: "A교무", role: :school_admin, password: "password")
    @librarian_a = User.create!(school: @school_a, name: "A사서", role: :librarian, password: "password")
    @superadmin = User.create!(name: "총괄", role: :superadmin, password: "password")

    @report_a1 = Report.create!(user: @student_a1, classroom: @class_a1, book_title: "A1 독후감")
    @report_a2 = Report.create!(user: @student_a2, classroom: @class_a2, book_title: "A2 독후감")
    @report_b1 = Report.create!(user: @student_b1, classroom: @class_b1, book_title: "B1 독후감")
  end

  test "report scope matrix keeps every role inside its boundary" do
    expected = {
      @student_a1  => [ @report_a1 ],
      @teacher_a1  => [ @report_a1 ],
      @teacher_a2  => [ @report_a2 ],
      @school_admin_a => [ @report_a1, @report_a2 ],
      @librarian_a => [ @report_a1, @report_a2 ],
      @superadmin  => [ @report_a1, @report_a2, @report_b1 ]
    }

    all_reports = [ @report_a1, @report_a2, @report_b1 ]

    expected.each do |user, permitted|
      resolved = ReportPolicy::Scope.new(user, Report.all).resolve.to_a
      assert_matches_boundary(all_reports, permitted, resolved, "Report / #{user.role} #{user.name}")
    end
  end

  test "classroom scope matrix keeps every role inside its boundary" do
    expected = {
      @student_a1  => [ @class_a1 ],
      @teacher_a1  => [ @class_a1 ],
      @teacher_a2  => [ @class_a2 ],
      @school_admin_a => [ @class_a1, @class_a2 ],
      @librarian_a => [ @class_a1, @class_a2 ],
      @superadmin  => [ @class_a1, @class_a2, @class_b1 ]
    }

    all_classrooms = [ @class_a1, @class_a2, @class_b1 ]

    expected.each do |user, permitted|
      resolved = ClassroomPolicy::Scope.new(user, Classroom.all).resolve.to_a
      assert_matches_boundary(all_classrooms, permitted, resolved, "Classroom / #{user.role} #{user.name}")
    end
  end

  private

  def assert_matches_boundary(all_records, permitted, resolved, label)
    permitted.each do |record|
      assert_includes resolved, record, "#{label} should see #{record.class}##{record.id}"
    end

    (all_records - permitted).each do |record|
      assert_not_includes resolved, record, "#{label} must not see out-of-boundary #{record.class}##{record.id}"
    end
  end
end
