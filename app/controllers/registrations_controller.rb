# 공개 회원가입은 교사 신청 전용(0.1). 학생 자가가입은 제거됐고 학생 계정은 담임교사가
# teacher/students 에서 생성한다. 교사 신청은 approved:false 로 생성되며 관리자 승인 전에는
# 로그인할 수 없다(세션 게이트). 가입 즉시 로그인시키지 않는다.
class RegistrationsController < ApplicationController
  skip_before_action :require_login, only: [ :new, :create ]

  def new
    load_form_collections
  end

  def create
    user = User.new(
      role: :teacher,
      approved: false,
      school_id: params[:school_id].presence,
      name: params[:name],
      password: params[:password]
    )

    unless user.valid?
      render_new_with_errors(user)
      return
    end

    # 학급 배정까지 원자적으로 처리한다. 학급 탈취(assign_classroom 가드) 시 롤백돼
    # 승인 대기 계정만 남는 고아 레코드가 생기지 않는다.
    User.transaction do
      user.save!
      assign_classroom(user)
    end

    redirect_to new_session_path, notice: "가입 신청이 접수됐어요. 관리자 승인 후 로그인할 수 있어요."
  end

  private

  def assign_classroom(user)
    return if params[:grade].blank? || params[:class_no].blank?

    classroom = Classroom.find_or_create_by!(
      school_id: user.school_id,
      grade: params[:grade],
      class_no: params[:class_no]
    )

    # 학급 탈취 방지: 이미 다른 교사가 담임인 학급은 재배정하지 않는다.
    raise Pundit::NotAuthorizedError if classroom.teacher_id.present? && classroom.teacher_id != user.id

    classroom.update!(teacher: user)
    user.update!(classroom: classroom)
  end

  def render_new_with_errors(user)
    load_form_collections
    flash.now[:alert] = user.errors.full_messages.to_sentence
    render :new, status: :unprocessable_entity
  end

  def load_form_collections
    @schools = School.order(:name)
    @classrooms = Classroom.order(:grade, :class_no)
  end
end
