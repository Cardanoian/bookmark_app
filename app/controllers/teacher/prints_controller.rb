# 교사 인쇄 문서(P6.3). 전용 print 레이아웃 + @media print CSS 로 표창장·가정통신문·
# 독서 포트폴리오(5축 방사형+뱃지)·학급 성장 리포트를 렌더한다. window.print() 친화.
class Teacher::PrintsController < Teacher::BaseController
  layout "print"

  before_action :set_classroom
  before_action :set_student, only: [ :award, :home_letter, :portfolio ]

  # 표창장
  def award
    @report = @student.reports.where.not(level: nil).order(:created_at).last
  end

  # 가정통신문
  def home_letter
    @reports = @student.reports.order(:created_at)
    @axis_averages = axis_averages(@reports.to_a)
  end

  # 독서 포트폴리오(5축 방사형 + 뱃지)
  def portfolio
    @reports = @student.reports.includes(:book).order(:created_at)
    @axis_averages = axis_averages(@reports.to_a)
    @axis_labels = ReadingDomain::RUBRIC_AXES.map { |axis| ReadingDomain::AXIS_LABELS[axis] }
    @badges = @student.badges
  end

  # 학급 성장 리포트
  def class_report
    @students = @classroom.users.where(role: :student).order(:name)
    @reports = Report.where(classroom_id: @classroom.id).includes(:user).to_a
    @axis_averages = axis_averages(@reports)
    @axis_labels = ReadingDomain::RUBRIC_AXES.map { |axis| ReadingDomain::AXIS_LABELS[axis] }
  end

  private

  def set_classroom
    @classroom = owned_classroom!(Classroom.find_by(id: params[:classroom_id]) || teacher_classrooms.first)
  end

  def set_student
    student =
      if params[:student_id].present?
        User.find(params[:student_id])
      else
        @classroom.users.where(role: :student).order(:name).first
      end
    raise ActiveRecord::RecordNotFound, "학생이 없습니다." unless student

    @student = owned_student!(student)
  end
end
