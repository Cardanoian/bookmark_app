# 교직원 비밀번호 재설정(이메일 링크). 비로그인 공개 흐름이라 `require_login` 을 건너뛰고,
# 인가할 리소스가 없어 fail-closed 안전망(`verify_authorized`)도 제외한다(선례: sessions·
# registrations·schools).
#
# **학생은 대상이 아니다.** 학생은 이메일 로그인 대상이 아니고(튜플 로그인) 담임이
# `Teacher::StudentsController#reset_password` 로 직접 초기화한다. 학생 계정에 어쩌다 이메일이
# 들어 있어도 `User#password_reset_eligible?` 가 fail-closed 로 막는다.
#
# **계정 열거를 막는다.** 존재하는 교직원·존재하지 않는 주소·학생·정지 계정 어느 경우에도 완전히
# 같은 안내 화면을 반환한다. 발송 실패 역시 사용자에게는 성공으로 보이며(의도된 트레이드오프),
# 유일한 관측 지점은 `MailDeliveryJob` 이 남기는 감사 로그다.
class PasswordResetsController < ApplicationController
  include MailRateLimiting

  skip_before_action :require_login
  skip_before_action :require_student_ranking_profile
  skip_after_action :verify_authorized

  def new
  end

  def create
    # 한도 초과도 **성공 화면과 구분되지 않게** 처리한다. 한도 초과 화면을 따로 보여주면
    # "이 주소는 한도에 걸렸다 = 이 주소로 요청이 있었다"는 신호가 새어 나간다.
    if mail_request_allowed?(**throttle_keys)
      deliver_reset_instructions
    end

    render :sent
  end

  def edit
    render :expired, status: :unprocessable_entity if token_user.nil?
  end

  def update
    user = token_user
    return render :expired, status: :unprocessable_entity if user.nil?

    # 빈 비밀번호는 has_secure_password 의 `password=` 가 무시해 "무변경 성공"으로 새어 나가므로
    # 명시적으로 막는다(PasswordsController 선례와 동일).
    return reject(user, "새 비밀번호를 입력해 주세요.") if params[:password].blank?

    if user.update(password: params[:password], password_confirmation: params[:password_confirmation])
      # 비밀번호가 바뀌면 password_salt 가 바뀌어 **방금 쓴 토큰을 포함해 발급된 모든 재설정
      # 토큰이 자동 무효**가 된다(User 의 generates_token_for 주석 참조).
      audit!("auth.password_reset_completed", target: user)
      reset_session
      redirect_to staff_login_path, notice: "비밀번호를 변경했어요. 새 비밀번호로 로그인해 주세요."
    else
      reject(user, "새 비밀번호를 확인해 주세요. (6자 이상, 새 비밀번호와 확인이 같아야 해요)")
    end
  end

  private

  # 자격이 되는 계정에만 실제로 보낸다. 판정 결과는 응답에 전혀 반영하지 않는다.
  def deliver_reset_instructions
    user = User.find_by(email: normalized_email)
    return unless user&.password_reset_eligible?

    AccountMailer.password_reset(user, user.generate_token_for(:password_reset)).deliver_later
    audit!("auth.password_reset_requested", target: user)
  end

  # 토큰이 위조·만료·비번 변경으로 무효면 nil(예외 없음). 자격 재확인을 여기서도 한 번 더 한다 —
  # 토큰 발급 후 역할이 바뀌거나 계정이 정지됐을 수 있다(발급 시점 판정만 믿지 않는다).
  def token_user
    return @token_user if defined?(@token_user)

    user = User.find_by_token_for(:password_reset, params[:token])
    @token_user = user&.password_reset_eligible? ? user : nil
  end

  def reject(user, message)
    @user = user
    flash.now[:alert] = message
    render :edit, status: :unprocessable_entity
  end

  # 계정 축은 **존재 여부와 무관하게 정규화 이메일**로 잡는다. user.id 로 키잉하면 미존재 주소가
  # 한도를 공유해 버려(또는 별도 버킷이 생겨) 열거 신호가 될 수 있다.
  def throttle_keys
    {
      ip_key: "mailreq:ip:#{request.remote_ip}",
      account_key: "mailreq:pwreset:#{normalized_email}"
    }
  end

  # 모델 저장 규칙(User#normalize_email)과 동일 — 앞뒤 공백 제거 + 소문자.
  def normalized_email
    params[:email].to_s.strip.downcase
  end
end
