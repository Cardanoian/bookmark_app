# 교사 학생 관리(P6.2). 담임 학급 학생 추가·삭제·비밀번호 초기화·수동 포인트 지급.
class Teacher::StudentsController < Teacher::BaseController
  before_action :set_student, only: [ :destroy, :reset_password, :give_points ]

  # 신규·초기화 시 부여하는 기본 비밀번호(has_secure_password 로 해시 저장).
  DEFAULT_PASSWORD = "1234"

  def index
    @classrooms = teacher_classrooms.order(:grade, :class_no).to_a
    @students = User.where(classroom_id: @classrooms.map(&:id), role: :student).order(:name)
  end

  def create
    classroom = owned_classroom!(target_classroom)
    @student = User.new(
      name: student_params[:name],
      classroom: classroom,
      school_id: classroom.school_id,
      role: :student,
      password: DEFAULT_PASSWORD
    )

    if @student.save
      redirect_to teacher_students_path, notice: "#{@student.name} 학생을 추가했어요. (기본 비밀번호 #{DEFAULT_PASSWORD})"
    else
      redirect_to teacher_students_path, alert: @student.errors.full_messages.to_sentence
    end
  end

  def destroy
    name = @student.name
    @student.destroy
    redirect_to teacher_students_path, notice: "#{name} 학생을 삭제했어요."
  end

  def reset_password
    @student.update!(password: DEFAULT_PASSWORD)
    redirect_to teacher_students_path, notice: "#{@student.name} 학생의 비밀번호를 초기화했어요."
  end

  def give_points
    amount = (params[:points].presence || 10).to_i
    @student.award_points(amount, reason: "교사 수동 지급")
    redirect_to teacher_students_path, notice: "#{@student.name} 학생에게 #{amount}포인트를 지급했어요."
  end

  private

  def set_student
    @student = owned_student!(User.find(params[:id]))
  end

  # 지정 학급(없으면 담임 첫 학급).
  def target_classroom
    Classroom.find_by(id: student_params[:classroom_id]) || teacher_classrooms.first
  end

  def student_params
    params.require(:student).permit(:name, :classroom_id)
  end
end
