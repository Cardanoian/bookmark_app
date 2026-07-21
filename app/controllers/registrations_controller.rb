# 공개 회원가입은 교사 신청 전용(0.1). 학생 자가가입은 제거됐고 학생 계정은 담임교사가
# teacher/students 에서 생성한다. 승인 게이트 없이 가입 즉시 로그인되어 바로 활동할 수 있다.
class RegistrationsController < ApplicationController
  skip_before_action :require_login, only: [ :new, :create ]
  # 공개 교사 신청 진입점 — 인가할 리소스가 없다(가입 전 비로그인 흐름).
  skip_after_action :verify_authorized

  def new
    load_form_collections
  end

  def create
    user = User.new(
      role: :teacher,
      school_id: params[:school_id].presence,
      name: params[:name],
      email: params[:email],
      password: params[:password]
    )

    # 교사는 이메일로 로그인하므로(sessions#staff_create) 가입 시 이메일을 필수로 받는다.
    # 모델은 형식·유일성만 검증하므로(presence 미강제) 여기서 빈 이메일을 명시적으로 막는다.
    # valid? 를 먼저 호출해 모델 검증으로 errors 를 채운 뒤(빈 이메일이면 normalize 로 nil),
    # presence 오류를 추가한다(valid? 가 뒤에 오면 수동 추가 오류가 지워지므로 순서가 중요).
    user.valid?
    user.errors.add(:email, "을(를) 입력해 주세요.") if user.email.blank?
    add_academic_year_error(user)

    unless user.errors.empty?
      render_new_with_errors(user)
      return
    end

    # 학급 배정까지 원자적으로 처리한다. 학급 탈취(assign_classroom 가드) 시 롤백돼
    # 고아 계정 레코드가 생기지 않는다.
    User.transaction do
      user.save!
      assign_classroom(user)
    end

    # 승인 게이트가 없으므로 가입 즉시 로그인시켜 바로 활동하게 한다.
    reset_session
    session[:user_id] = user.id
    redirect_to root_path, notice: "가입이 완료됐어요. 책갈피에 오신 걸 환영해요!"
  end

  private

  def assign_classroom(user)
    return if params[:grade].blank? || params[:class_no].blank?

    classroom = Classroom.find_or_create_by!(
      school_id: user.school_id,
      academic_year: params[:academic_year].presence || Classroom.current_academic_year,
      grade: params[:grade],
      class_no: params[:class_no]
    )

    # 학급 탈취 방지: 이미 다른 교사가 담임인 학급은 재배정하지 않는다.
    raise Pundit::NotAuthorizedError if classroom.teacher_id.present? && classroom.teacher_id != user.id

    classroom.update!(teacher: user)
    user.update!(classroom: classroom)
  end

  # 학년도는 학급이 만들어질 때만(grade·class_no 존재) 의미가 있다. 범위 밖·비정수 입력을
  # find_or_create_by! 가 RecordInvalid(422 정적 페이지·폼 유실)로 던지기 전에 여기서 잡아
  # 이메일 오류와 동일하게 friendly 재렌더한다. 빈 값은 assign_classroom 이 현재 학년도로 폴백한다.
  def add_academic_year_error(user)
    return if params[:grade].blank? || params[:class_no].blank? || params[:academic_year].blank?

    year = params[:academic_year].to_s.strip
    return if year.match?(/\A\d+\z/) && year.to_i.between?(2001, 2999)

    user.errors.add(:base, "학년도는 2001~2999 사이로 입력해 주세요.")
  end

  def render_new_with_errors(user)
    load_form_collections
    flash.now[:alert] = user.errors.full_messages.to_sentence
    render :new, status: :unprocessable_entity
  end

  # 가입 학교 피커는 하이브리드(이름검색+시도→시군구 캐스케이딩)라 전량 로드하지 않고
  # 시도(교육청) 목록만 서버 렌더한다. 학급은 number_field(grade/class_no)라 학급 로드 불요.
  def load_form_collections
    @regions = School.form_regions
    @current_academic_year = Classroom.current_academic_year
  end
end
