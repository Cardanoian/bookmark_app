class SessionsController < ApplicationController
  # 로그인 브루트포스 방어(0.5). 동일 IP 기준 3분 내 10회 초과 시도부터 차단하고,
  # 429 대신 로그인 화면으로 친절히 되돌린다.
  #
  # rate_limit 은 store 를 클래스 로드 시 1회 캡처하므로, 위임 대상(target)을 런타임에
  # 교체할 수 있는 얇은 프록시로 감싼다. 기본 target 은 앱 캐시(프로덕션 Solid Cache).
  # 테스트 캐시는 :null_store 라 카운팅이 안 되므로, 스로틀 테스트에서만 target 을
  # 카운팅 가능한 인메모리 스토어로 바꿔 검증한다(그 외 테스트는 무카운팅 → 무스로틀).
  #
  # 주의: RATE_LIMIT_STORE 는 가변 싱글턴이다. Rails 기본 테스트 병렬화는 프로세스 단위라
  # 각 워커가 독립 상수를 가져 안전하며, 테스트는 teardown 에서 target 을 되돌린다.
  # 스레드 단위 병렬화로 전환한다면 이 target 교체는 경쟁 상태가 되므로 재검토가 필요하다.
  class RateLimitStore
    attr_accessor :target

    def initialize(target)
      @target = target
    end

    def increment(name, amount = 1, **options)
      @target.increment(name, amount, **options)
    end
  end

  RATE_LIMIT_STORE = RateLimitStore.new(Rails.cache)

  rate_limit to: 10, within: 3.minutes,
             store: RATE_LIMIT_STORE,
             with: -> { redirect_to new_session_path, alert: "로그인 시도가 너무 많아요. 잠시 후 다시 시도해 주세요." },
             only: :create

  skip_before_action :require_login, only: [ :new, :create ]
  # 로그인/로그아웃 진입점 — 인가할 리소스가 없다(공개·인증 흐름).
  skip_after_action :verify_authorized

  def new
    load_form_collections
  end

  def create
    user = User.find_by(
      school_id: params[:school_id].presence,
      classroom_id: params[:classroom_id].presence,
      name: params[:name]
    )

    authenticated = user&.authenticate(params[:password])

    if authenticated && user.suspended?
      load_form_collections
      flash.now[:alert] = "정지된 계정입니다. 관리자에게 문의해 주세요."
      render :new, status: :forbidden
    elsif authenticated && user.teacher? && !user.approved?
      load_form_collections
      flash.now[:alert] = "관리자 승인 후 로그인할 수 있어요."
      render :new, status: :forbidden
    elsif authenticated
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
