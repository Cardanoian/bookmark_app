class RegistrationsController < ApplicationController
  skip_before_action :require_login, only: [ :new, :create ]

  ALLOWED_ROLES = %w[student teacher].freeze

  def new
    load_form_collections
  end

  def create
    role = params[:role].to_s

    unless ALLOWED_ROLES.include?(role)
      redirect_to new_registration_path, alert: "학생 또는 교사만 가입할 수 있습니다."
      return
    end

    role == "teacher" ? create_teacher : create_student
  end

  private

  def create_student
    user = User.new(
      role: :student,
      school_id: params[:school_id].presence,
      classroom_id: params[:classroom_id].presence,
      name: params[:name],
      password: params[:password]
    )

    if user.save
      sign_in(user)
    else
      render_new_with_errors(user)
    end
  end

  def create_teacher
    user = User.new(
      role: :teacher,
      school_id: params[:school_id].presence,
      name: params[:name],
      password: params[:password]
    )

    if user.save
      assign_classroom(user)
      sign_in(user)
    else
      render_new_with_errors(user)
    end
  end

  def assign_classroom(user)
    return if params[:grade].blank? || params[:class_no].blank?

    classroom = Classroom.find_or_create_by!(
      school_id: user.school_id,
      grade: params[:grade],
      class_no: params[:class_no]
    )
    classroom.update!(teacher: user)
    user.update!(classroom: classroom)
  end

  def sign_in(user)
    reset_session
    session[:user_id] = user.id
    redirect_to root_path
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
