# 교사 학생 관리(P6.2). 담임 학급 학생 추가·삭제·비밀번호 초기화·수동 포인트 지급.
class Teacher::StudentsController < Teacher::BaseController
  before_action :set_student, only: [ :destroy, :reset_password, :give_points ]

  def index
    @classrooms = teacher_classrooms.order(:academic_year, :grade, :class_no).to_a
    @students = User.where(classroom_id: @classrooms.map(&:id), role: :student).order(:name)
  end

  def create
    classroom = owned_classroom!(target_classroom)
    password = student_params[:password]
    if password.blank?
      return redirect_to teacher_students_path, alert: "비밀번호를 6자 이상 입력해 주세요."
    end

    @student = User.new(
      name: student_params[:name],
      classroom: classroom,
      school_id: classroom.school_id,
      role: :student,
      password: password
    )

    if @student.save
      redirect_to teacher_students_path, notice: "#{@student.name} 학생을 추가했어요."
    else
      redirect_to teacher_students_path, alert: @student.errors.full_messages.to_sentence
    end
  end

  def destroy
    name = @student.name
    User.transaction do
      @student.destroy!
      audit!("teacher.student_delete", target: @student)
    end
    redirect_to teacher_students_path, notice: "#{name} 학생을 삭제했어요."
  end

  def reset_password
    password = params.permit(student: [ :password ]).dig(:student, :password)
    if password.blank?
      return redirect_to teacher_students_path, alert: "비밀번호를 6자 이상 입력해 주세요."
    end

    updated = User.transaction do
      next false unless @student.update(password: password)

      audit!("teacher.password_reset", target: @student)
      true
    end

    if updated
      redirect_to teacher_students_path, notice: "#{@student.name} 학생의 비밀번호를 초기화했어요."
    else
      redirect_to teacher_students_path, alert: "비밀번호를 6자 이상 입력해 주세요."
    end
  end

  def give_points
    raw_amount = params[:points].presence || "10"
    unless raw_amount.to_s.match?(/\A[1-9]\d*\z/)
      return redirect_to teacher_students_path, alert: "선물할 포인트는 1 이상의 정수여야 해요."
    end

    amount = raw_amount.to_i
    points_before = @student.points
    User.transaction do
      @student.award_points(amount, reason: "교사 수동 지급")
      audit!(
        "teacher.points_grant",
        target: @student,
        metadata: { amount: amount, points_before: points_before, points_after: @student.points }
      )
    end
    redirect_to teacher_students_path,
                notice: "#{@student.name} 학생에게 #{amount}포인트와 #{amount}경험치를 지급했어요."
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
    params.require(:student).permit(:name, :classroom_id, :password)
  end
end
