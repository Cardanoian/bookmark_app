# 교사 가입 이메일 인증(resend). 인증 완료 시각을 기록한다.
#
# **토큰 컬럼은 두지 않는다.** 재설정·인증 토큰은 Rails 8 의 `generates_token_for` 로 발급하며
# 비밀번호 salt / 이메일에 바인딩돼 상태 저장 없이 무효화된다(`User` 참조). 토큰을 DB 에 두면
# purge 잡·보존기간 관리(선례: `account_merges.snapshot` 의 `Accounts::PurgeCredentialsJob`)를
# 하나 더 떠안게 되므로 피했다.
#
# 인덱스도 두지 않는다 — 이 컬럼은 조회 축이 아니라 현재 사용자 1명에 대한 술어로만 읽힌다.
class AddEmailVerifiedAtToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :email_verified_at, :datetime

    # 기존 계정 백필. 이 기능 이전에 만들어진 교직원 계정을 미인증으로 두면 데모 계정
    # (`DemoAccounts::TEACHER_EMAIL` = jieun@gbeai.net)·시드 교직원·실사용 교사가 전부 인증
    # 게이트에 걸려 학생 계정 생성이 막히는 회귀가 된다. 학생은 이메일 로그인 대상이 아니라
    # NULL 로 둔다(게이트도 teacher? 로 한정돼 학생과 무관).
    #
    # update_all 이라 updated_at 은 갱신되지 않는다 — 백필은 사용자 행동이 아니므로 의도된 것이다
    # (선례: 20260718000002 의 celebrated_at 백필).
    User.where.not(role: :student).where.not(email: nil).update_all(email_verified_at: Time.current)
  end

  def down
    remove_column :users, :email_verified_at
  end
end
