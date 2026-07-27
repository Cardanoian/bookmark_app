# 계정 인증 메일(교직원 비밀번호 재설정 · 교사 가입 이메일 인증).
#
# 두 메일 모두 **학생에게는 가지 않는다** — 학생은 이메일 로그인 대상이 아니고(튜플 로그인)
# 비밀번호는 담임이 직접 초기화한다. 호출부(PasswordResetsController·RegistrationsController·
# EmailVerificationsController)가 역할을 판정한 뒤에만 이 메일러를 호출한다.
#
# 만료 시간 문구는 뷰에 하드코딩하지 않고 `@expires_in_text` 로 주입한다. 상수(`User::…_EXPIRY`)를
# 바꾸면 본문 문구가 자동으로 따라오므로, 문서와 코드가 어긋나 "메일은 15분이라는데 실제로는
# 30분" 같은 드리프트가 생기지 않는다(메일러 테스트가 이 일치를 검증).
class AccountMailer < ApplicationMailer
  def password_reset(user, token)
    @user = user
    @url = edit_password_reset_url(token: token)
    @expires_in_text = duration_text(User::PASSWORD_RESET_EXPIRY)

    mail(to: @user.email, subject: "[책갈피] 비밀번호 재설정 안내")
  end

  def email_verification(user, token)
    @user = user
    @url = email_verification_url(token: token)
    @expires_in_text = duration_text(User::EMAIL_VERIFICATION_EXPIRY)

    mail(to: @user.email, subject: "[책갈피] 이메일 주소 확인 안내")
  end

  private

  # 안내 화면(password_resets/sent 등)과 같은 표기를 쓰도록 뷰 헬퍼를 공유한다.
  def duration_text(duration)
    ApplicationController.helpers.duration_ko(duration)
  end
end
