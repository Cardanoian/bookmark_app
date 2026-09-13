class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include MonsterDiscovery

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_current_user
  before_action :enforce_not_suspended
  before_action :require_login
  before_action :require_student_ranking_profile

  helper_method :current_user, :logged_in?, :ocr_available?, :reading_discussion_enabled?,
                :email_verification_banner?

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # 인가 안전망(2.9): 액션이 authorize 를 호출하지 않으면 예외로 실패시킨다(fail-closed).
  # 향후 authorize 누락 액션이 조용히 열리는 fail-open 을 예방한다. 공개·역할게이트·
  # 표현용 액션은 각 컨트롤러에서 이유를 달아 skip_after_action 으로 제외한다.
  after_action :verify_authorized

  private

  # 사진(OCR) 입력 모드 사용 가능 여부. OCR 만 Gemini 를 쓰므로 **Gemini 키**가 없으면 false 다
  # (P3.5). 첨삭 등 다른 AI 는 Claude 키를 보므로 두 키는 독립적으로 켜고 끌 수 있다 —
  # Gemini 키만 없으면 사진 모드만 사라지고 첨삭은 그대로 동작한다.
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

    redirect_to new_session_path
  end

  # 미인증 이메일 배너 노출 여부. 발송이 불가능한 환경(무키 개발·CI·오프라인 시연)에서는
  # '다시 보내기'가 아무 일도 못 하므로 배너 자체를 띄우지 않는다(죽은 버튼 방지 —
  # sessions#new 의 체험 계정 섹션이 계정 존재 여부로 게이트하는 것과 같은 규약).
  def email_verification_banner?
    Mail::ResendGateway.available? && current_user&.email_verification_pending?
  end

  # 이메일 인증 게이트. **남의 계정을 만들고 조작하는 액션에만** 건다(학생 계정 생성·비번 초기화).
  # 읽기·검토는 계속 허용해 "잠기는 실패"를 만들지 않는다(User#email_verification_gate_active?
  # 주석 참조 — 목적은 침입자 차단이 아니라 본인 계정의 복구 가능성 확보).
  def require_verified_email!
    return unless current_user&.email_verification_gate_active?

    redirect_back fallback_location: root_path,
                  alert: "이메일 주소를 먼저 확인해 주세요. 확인해야 비밀번호를 잊으셨을 때 되찾을 수 있어요."
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

  # 기존 학생도 배포 뒤 첫 요청에서 닉네임·랭킹 참여 여부를 한 번 명시하게 한다.
  # 설정 컨트롤러는 이 콜백을 skip 해 리다이렉트 루프를 끊는다.
  def require_student_ranking_profile
    return unless current_user&.student?
    return if current_user.ranking_profile_complete?

    redirect_to edit_ranking_preference_path,
                alert: "먼저 사용할 닉네임과 랭킹 참여 여부를 정해 주세요."
  end

  def audit!(action, target: nil, school_id: nil, classroom_id: nil, metadata: {})
    AuditLogger.record!(
      actor: Current.user || current_user,
      action: action,
      target: target,
      request: request,
      school_id: school_id,
      classroom_id: classroom_id,
      metadata: metadata
    )
  end

  # 챌린지 참여 후 첫 작성 글에 challenge_id 를 연결한다(참여 플래그는 ChallengesController#join 이 세션에 남김).
  # 새 글을 만드는 두 곳 — ReportsController#create 와 단계 학습을 마친 LearnController — 이 함께 쓴다(챌린지
  # 순위가 이 연결로 센다, RankingBoard#challenge_ranking). 플래그는 여기서 읽기만 하고, 그 글이 실제로 저장돼
  # 챌린지에 **이어졌을 때만** consume_participation 으로 지운다(1회성) — 빈 본문·입력 오류로 되돌아간 요청이 먼저
  # 지우면 이어서 쓴 글이 챌린지에 연결되지 않았다(자동 저장 6차 리뷰 F-5). 이어지지 않은 글(시작 전 챌린지)은 표를
  # 남겨 기간 안의 첫 글에 잇는다.
  # [menu_refactor 심화 PR6] 미션 분기는 제거했다 — 미션은 세션 참여가 아니라 발행 시 자동 배정되고
  # 승인·게임 이벤트로 자동 진행되므로 reports.mission_id 연결이 필요 없다(챌린지 분기만 유지).
  #
  # 진행 중인 챌린지에만 잇는다. 표가 남는 경우(되돌아간 요청)가 생긴 뒤로는, 끝난 챌린지의 표가 그 뒤에 쓴 글에 붙어
  # 순위에 셌다(7차 리뷰 F7-4). 없어졌거나 끝난 챌린지의 표는 다시 쓸 일이 없어 버린다. 아직 시작 전이면 잇지 않고 둔다.
  def link_participation(report)
    challenge_id = session[:active_challenge_id]
    return unless challenge_id

    challenge = Challenge.find_by(id: challenge_id)
    if challenge&.active?
      report.challenge_id = challenge.id
    elsif challenge.nil? || (challenge.window_end && Date.current > challenge.window_end)
      consume_participation
    end
  end

  def consume_participation
    session.delete(:active_challenge_id)
  end

  # 독서 토론 기능 플래그(reading_discussion). 신고·모더레이션·금칙어 안전 스택을 함께 출하하므로
  # **기본값은 활성(확대, default: true)** 이며, 관리자는 전역 하드 kill(feature_flags 에
  # "reading_discussion" => false) 또는 학급/학교 스코프 off 오버라이드로만 차단한다
  # (on_demand_games 규약과 동일). 학급 파일럿→확대 롤아웃도 스코프 오버라이드로 가능.
  def reading_discussion_enabled?(user = current_user)
    AppSetting.feature_enabled?("reading_discussion", scope: user, default: true)
  end

  # 토론 컨트롤러 진입 게이트. 뷰만 가리는 것으로는 URL 직접 요청을 막지 못하므로 컨트롤러에서
  # 강제한다(kill switch·파일럿 격리 실효 보장). 비활성 시 홈으로 리다이렉트해 액션을 중단한다
  # (before_action 리다이렉트는 이후 콜백·verify_authorized 를 건너뛴다).
  def require_reading_discussion!
    return if reading_discussion_enabled?

    redirect_to root_path, alert: "지금은 독서 토론을 이용할 수 없어요."
  end
end
