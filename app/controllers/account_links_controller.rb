# 계정 연동(MERGE) 학생 셀프서브(account_linking_seasons_plan §Phase 3). 학년이 바뀌어 새 담임이
# 만든 **현재 학년도 placeholder(=로그인 중인 current_user)** 로 접속한 학생이, **작년 계정의 자격증명
# (학교·학급·이름·비번)** 을 증명해 두 계정을 병합한다. 병합은 작년 계정을 생존자로 남기고(기록 이월)
# placeholder 를 삭제한 뒤 세션을 생존자로 스왑한다(현재 학급·이름·비번은 승계돼 그대로 로그인 유지).
#
# 보안: 자격증명 인증은 Sessions 와 같은 fail2ban(LoginThrottling)을 쓰되 **계정 축은 공유·IP 축은
# 분리**한다. preview 는 비번을 저장하지 않고 서명 토큰(MessageVerifier, 5분·new/old 바인딩)만 발급하며,
# confirm 은 그 토큰만으로 병합한다. 실제 병합 가드(학년도 경계·정지·소유)는 MergeService 가 강제한다.
class AccountLinksController < ApplicationController
  include LoginThrottling

  before_action :require_account_linking!

  # 연동 폼(작년 학교·학급·이름·비번).
  def new
    authorize :account_link, :new?
    load_form_collections
  end

  # 작년 자격증명 인증(스로틀 하) → 이월 자산 미리보기 + 서명 토큰 발급. 비번은 저장하지 않는다.
  def preview
    authorize :account_link, :preview?

    old = find_old_student
    keys = throttle_keys_for(old)

    if old&.authenticate(params[:password])
      # 정답 = 브루트포스 아님 → 두 축 실패 카운터 해제(피해자 DoS·NAT 방지).
      reset_login_failures(**keys)
      show_preview_or_reject(old)
    elsif locked_out?(**keys)
      rerender_new("시도가 너무 많아요. 잠시 후 다시 시도해 주세요.", :too_many_requests)
    else
      register_login_failure(**keys)
      rerender_new("작년 학교·학급·이름·비밀번호를 다시 확인해 주세요.", :unprocessable_entity)
    end
  end

  # 서명 토큰 검증(만료·new_id 바인딩) → 병합 실행 → 커밋 후 사이드이펙트 + 세션 스왑.
  def confirm
    authorize :account_link, :confirm?

    payload = verified_token
    unless payload && payload["new_id"].to_i == current_user.id
      redirect_to new_account_link_path, alert: "연동 정보가 만료됐어요. 다시 시도해 주세요."
      return
    end

    old = User.find_by(id: payload["old_id"].to_i)
    service = merge_service(old)
    result = service.call

    if result.ok?
      # 커밋 후에만 사이드이펙트(reload·뱃지·진화·랭킹 방송·해금) — 서비스가 아니라 호출자 책임.
      service.run_post_commit_side_effects!(result.surviving_user)
      # handle_authenticated 와 동일 패턴: 세션을 생존자로 스왑(CSRF rotate 전파, turbo_stream 금지).
      reset_session
      session[:user_id] = result.surviving_user.id
      redirect_to profile_path, notice: "작년 계정과 연동됐어요! 그동안의 기록을 이어서 볼 수 있어요."
    else
      redirect_to new_account_link_path, alert: confirm_error_message(result.error_code)
    end
  end

  private

  # 기능 플래그 게이트(파일럿 격리·롤아웃). off 면 안내 후 홈으로(before_action 리다이렉트는 이후
  # 콜백·verify_authorized 를 건너뛴다 — require_reading_discussion! 선례).
  def require_account_linking!
    return if account_linking_enabled?

    redirect_to root_path, alert: "지금은 계정 연동을 이용할 수 없어요."
  end

  def account_linking_enabled?
    AppSetting.feature_enabled?("account_linking", scope: current_user&.classroom, default: false)
  end

  # 작년 계정 인증 성공 후: 유효한 이월 원천이면 미리보기, 아니면(자기 계정·현재 학년도) 거부.
  def show_preview_or_reject(old)
    if valid_old_source?(old)
      @old = old
      @preview = merge_service(old).preview
      @token = issue_token(old)
      render :preview
    else
      rerender_new("그 계정으로는 연동할 수 없어요. 작년(지난 학년도) 계정 정보가 맞는지 확인해 주세요.",
                   :unprocessable_entity)
    end
  end

  # 이월 원천 유효성: 자기 자신이 아니고, 학급이 있으며, 지난 학년도 학급이어야 한다.
  # (엄밀한 병합 가드는 MergeService 가 재확인 — 여기선 미리보기·토큰 발급 전 1차 방어.)
  def valid_old_source?(old)
    return false if old.id == current_user.id

    year = old.classroom&.academic_year
    year.present? && year < Classroom.current_academic_year
  end

  # 작년 계정 튜플 신원(학교·학급·이름) 조회. 스로틀 키·인증에서 공유하도록 메모이즈.
  def find_old_student
    return @find_old_student if defined?(@find_old_student)

    @find_old_student = User.student.find_by(
      school_id: params[:school_id].presence,
      classroom_id: params[:classroom_id].presence,
      name: params[:name]
    )
  end

  # 스로틀 두 축 키. **계정 축은 Sessions 와 공유**(login:account:user:<old.id> — 존재 계정은 Sessions 의
  # 학생 키와 동일 버킷이라 자격증명 브루트포스 표면을 합산), **IP 축은 분리**(linkauth:ip:* — NAT 뒤
  # 로그인 가용성이 연동 시도로 오염되지 않게 별도 네임스페이스).
  def throttle_keys_for(old)
    account_id = old ? "user:#{old.id}" : failed_account_key
    { ip_key: "linkauth:ip:#{request.remote_ip}", account_key: "login:account:#{account_id}" }
  end

  # 미존재(오타/추측) 계정의 스로틀 계정 키(Sessions 미존재 튜플 정규화와 동형).
  def failed_account_key
    [ params[:school_id].to_i, params[:classroom_id].to_i, params[:name].to_s.strip.downcase ].join(":")
  end

  def merge_service(old)
    Accounts::MergeService.new(old_account: old, new_account: current_user, performed_by: current_user)
  end

  # 서명 토큰: 5분 만료 + new(현재 세션)·old 바인딩. 비번을 저장하지 않고 preview→confirm 사이를 잇는다.
  def issue_token(old)
    link_verifier.generate({ "new_id" => current_user.id, "old_id" => old.id }, expires_in: 5.minutes)
  end

  # 토큰 검증(위·변조·만료 시 nil — verified 는 예외 없이 nil 반환).
  def verified_token
    link_verifier.verified(params[:token])
  end

  def link_verifier
    Rails.application.message_verifier(:account_link)
  end

  def confirm_error_message(code)
    case code
    when :invalid_source, :invalid_target, :same_account
      "연동 조건이 맞지 않아요. 작년(지난 학년도) 계정인지 확인해 주세요."
    when :suspended
      "정지된 계정은 연동할 수 없어요. 선생님께 문의해 주세요."
    when :claim_conflict
      "이미 다른 연동이 처리 중이에요. 잠시 후 다시 시도해 주세요."
    else
      "연동을 처리하지 못했어요. 잠시 후 다시 시도해 주세요."
    end
  end

  def rerender_new(message, status)
    load_form_collections
    flash.now[:alert] = message
    render :new, status: status
  end

  # 연동 폼 학교 피커는 하이브리드라 시도(교육청) 목록만 서버 렌더한다(학급은 AJAX 스코프 조회).
  # 작년 계정을 찾으므로 학년도 기본값은 지난 학년도(current-1)로 둔다(뷰에서 피커에 전달).
  def load_form_collections
    @regions = School.form_regions
    @current_academic_year = Classroom.current_academic_year
  end
end
