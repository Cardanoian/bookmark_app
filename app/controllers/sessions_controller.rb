class SessionsController < ApplicationController
  skip_before_action :require_login, only: [ :new, :create ]

  def new
    load_form_collections
  end

  def create
    user = User.find_by(
      school_id: params[:school_id].presence,
      classroom_id: params[:classroom_id].presence,
      name: params[:name]
    )

    if user&.authenticate(params[:password]) && user.suspended?
      load_form_collections
      flash.now[:alert] = "정지된 계정입니다. 관리자에게 문의해 주세요."
      render :new, status: :forbidden
    elsif user&.authenticate(params[:password])
      reset_session
      session[:user_id] = user.id
      redirect_to root_path
    else
      load_form_collections
      flash.now[:alert] = "학교·학급·이름·비밀번호를 다시 확인해 주세요."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to new_session_path
  end

  private

  def load_form_collections
    @schools = School.order(:name)
    @classrooms = Classroom.order(:grade, :class_no)
  end
end
