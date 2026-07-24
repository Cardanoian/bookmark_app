# 마이페이지 비밀번호 변경(본인 전용). current_user 본인만 다뤄 리소스 인가 대상이 없으므로
# fail-closed 인가 안전망을 우회한다(선례: sessions·registrations·schools). 비로그인 접근은
# ApplicationController 의 require_login 이 막는다.
class PasswordsController < ApplicationController
  skip_after_action :verify_authorized

  def edit
  end

  # 현재 비밀번호를 **먼저** 확인(변조 전 다이제스트 기준)한 뒤 새 비밀번호로 갱신한다. 확인과
  # 갱신을 분리해, 새 비밀번호가 검증에 걸려 current_user 가 메모리에서 변조돼도(has_secure_password
  # 의 password= 가 digest 를 갈아끼운다) 현재 비밀번호 확인이 오판되지 않게 한다. 빈 새 비밀번호는
  # password= 가 무시해 "무변경 성공"으로 새어 나가므로 명시적으로 막는다.
  def update
    return reject("현재 비밀번호가 일치하지 않아요.") unless current_user.authenticate(params[:current_password])
    return reject("새 비밀번호를 입력해 주세요.") if params[:password].blank?

    if current_user.update(password: params[:password], password_confirmation: params[:password_confirmation])
      redirect_to profile_path, notice: "비밀번호를 변경했어요."
    else
      reject("새 비밀번호를 확인해 주세요. (6자 이상, 새 비밀번호와 확인이 같아야 해요)")
    end
  end

  private

  def reject(message)
    flash.now[:alert] = message
    render :edit, status: :unprocessable_entity
  end
end
