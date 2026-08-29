# 교사 인쇄 문서(P6.3). 전용 print 레이아웃 + @media print CSS 로 표창장·가정통신문·
# 독서 포트폴리오(5축 방사형+뱃지)·학급 성장 리포트를 렌더한다. window.print() 친화.
#
# `index` 는 그 4종의 **진입 화면**이다. 오랫동안 이 문서들은 웹·앱 어디에도 링크가 없어
# URL 을 직접 치는 사람만 닿을 수 있었다(계획 Phase 7 이 남긴 별건). 인쇄물이 아니라 교사
# 콘솔의 일반 화면이므로 print 레이아웃을 쓰지 않는다.
class Teacher::PrintsController < Teacher::BaseController
  # 문서 4종만 인쇄 전용 레이아웃. index 는 교사 콘솔 네비가 있는 일반 레이아웃이다.
  layout -> { action_name == "index" ? "application" : "print" }

  before_action :set_classroom, except: [ :index ]
  before_action :set_index_scope, only: [ :index ]
  before_action :set_student, only: [ :award, :home_letter, :portfolio ]

  # 문서 출력 인덱스 — 학급 성장 리포트(학급 1개) + 학생별 문서 3종(표창장·가정통신문·포트폴리오).
  def index; end

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

  # index 전용 스코프. 문서 4종과 달리 **담당 학급이 하나도 없어도 403 이 아니라 빈 상태**로 연다 —
  # 네비에 상시 노출되는 화면이라 학급 배정 전 교사가 눌렀다고 권한 오류를 띄우면 안 된다.
  # 위조된 classroom_id 는 그대로 403(owned_classroom!)이다.
  def set_index_scope
    @classrooms = teacher_classrooms.order(:academic_year, :grade, :class_no).to_a
    requested = Classroom.find_by(id: params[:classroom_id])
    @classroom = requested ? owned_classroom!(requested) : @classrooms.first
    @students = @classroom ? User.where(classroom_id: @classroom.id, role: :student).order(:name).to_a : []
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
