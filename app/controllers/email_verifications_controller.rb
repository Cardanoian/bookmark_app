# 교사 가입 이메일 인증. 두 표면의 성격이 다르다:
#   · `show`  = 메일 링크(토큰). **비로그인 허용** — 메일을 다른 기기·브라우저에서 열 수 있다.
#   · `create` = 재발송. **로그인 필요** — 본인 계정에만 다시 보낸다.
#
# 재발송에는 **계정 열거 방지를 적용하지 않는다.** 요청자가 이미 자기 계정으로 로그인해 있어
# 누설할 정보가 없고, 오히려 실패를 숨기면 "메일이 안 오는데 앱은 성공이라 한다"는 진단 불가
# 상태만 남는다(비밀번호 재설정은 비로그인 표면이라 반대로 항상 동일 응답을 준다).
#
# `show` 가 GET 으로 상태를 바꾸는 것은 메일 링크의 불가피한 형태다. 인증은 **멱등**(이미 인증된
# 계정은 시각을 덮어쓰지 않음)이고 결과가 계정에 이롭기만 해서, 메일 스캐너가 링크를 선인출해도
# 피해가 없다.
class EmailVerificationsController < ApplicationController
  include MailRateLimiting

  skip_before_action :require_login, only: [ :show ]
  skip_before_action :require_student_ranking_profile
  # 토큰 소지 자체가 자격이고(show), 재발송은 current_user 본인만 다룬다(create) — 인가할
  # 리소스가 없다(선례: sessions·registrations·passwords).
  skip_after_action :verify_authorized

  def show
    user = User.find_by_token_for(:email_verification, params[:token])

    if user.nil?
      redirect_to root_path, alert: "인증 링크를 쓸 수 없어요. 로그인한 뒤 인증 메일을 다시 받아 주세요."
    elsif user.email_verified?
      redirect_to root_path, notice: "이미 확인된 이메일 주소예요."
    else
      user.update_columns(email_verified_at: Time.current, updated_at: Time.current)
      audit!("auth.email_verified", target: user)
      redirect_to root_path, notice: "이메일 주소를 확인했어요. 고맙습니다!"
    end
  end

  def create
    return redirect_back_with("이미 확인된 이메일 주소예요.", :notice) if current_user.email_verified?
    return redirect_back_with("이메일 주소가 없어 인증 메일을 보낼 수 없어요.") if current_user.email.blank?

    unless mail_request_allowed?(**throttle_keys)
      return redirect_back_with("인증 메일을 너무 자주 보냈어요. 잠시 후 다시 시도해 주세요.")
    end

    EmailVerifications.deliver(current_user)
    audit!("auth.email_verification_sent", target: current_user)
    redirect_back_with("인증 메일을 다시 보냈어요. 메일함을 확인해 주세요.", :notice)
  end

  private

  def redirect_back_with(message, kind = :alert)
    redirect_back fallback_location: root_path, kind => message
  end

  def throttle_keys
    {
      ip_key: "mailreq:ip:#{request.remote_ip}",
      account_key: "mailreq:verify:user:#{current_user.id}"
    }
  end
end
