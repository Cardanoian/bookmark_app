class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_current_user
  before_action :enforce_not_suspended
  before_action :require_login

  helper_method :current_user, :logged_in?, :ocr_available?

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  # 사진(OCR) 입력 모드 사용 가능 여부. Gemini 키가 없으면 false (P3.5).
  def ocr_available?
    Ai::GeminiClient.available?
  end

  def set_current_user
    Current.user = current_user
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    return if logged_in?

    redirect_to new_session_path, alert: "로그인이 필요합니다."
  end

  # 세션 도중 계정이 정지되면 즉시 로그아웃한다(P7.2).
  def enforce_not_suspended
    return unless current_user&.suspended?

    reset_session
    @current_user = nil
    Current.user = nil
    redirect_to new_session_path, alert: "정지된 계정입니다. 관리자에게 문의해 주세요."
  end

  def user_not_authorized
    head :forbidden
  end
end
