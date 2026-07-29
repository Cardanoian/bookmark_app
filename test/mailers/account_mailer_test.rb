require "test_helper"

# 계정 인증 메일(비밀번호 재설정 · 가입 이메일 인증)의 봉투·본문 계약.
class AccountMailerTest < ActionMailer::TestCase
  setup do
    @school = School.create!(name: "메일학교")
    @teacher = User.create!(name: "김선생", email: "mailer-teacher@example.com",
                            role: :teacher, school: @school, password: "password")
  end

  test "password_reset addresses the verified sender and the recipient" do
    mail = AccountMailer.password_reset(@teacher, "TOKEN123")

    assert_equal [ "mailer-teacher@example.com" ], mail.to
    assert_equal "[책갈피] 비밀번호 재설정 안내", mail.subject
    assert_includes mail.from, "admin@chaekgalpi.net"
  end

  test "password_reset renders both html and text parts with the token link" do
    mail = AccountMailer.password_reset(@teacher, "TOKEN123")
    html, text = parts_of(mail)

    [ html, text ].each do |body|
      assert_includes body, "TOKEN123", "두 파트 모두에 재설정 링크가 있어야 한다"
      assert_includes body, @teacher.name
    end
    assert_includes html, "비밀번호 재설정하기"
  end

  test "password_reset states the expiry that matches the constant" do
    mail = AccountMailer.password_reset(@teacher, "TOKEN123")
    expected = ApplicationController.helpers.duration_ko(User::PASSWORD_RESET_EXPIRY)

    parts_of(mail).each do |body|
      assert_includes body, expected,
                      "본문 만료 문구는 User::PASSWORD_RESET_EXPIRY 에서 파생돼야 한다(문서-코드 드리프트 차단)"
    end
  end

  test "password_reset never leaks the plaintext password or its digest" do
    @teacher.update!(password: "Distinctive-Secret-9182")
    mail = AccountMailer.password_reset(@teacher, "TOKEN123")

    parts_of(mail).each do |body|
      assert_not_includes body, "Distinctive-Secret-9182", "평문 비밀번호가 메일에 실려서는 안 된다"
      assert_not_includes body, @teacher.password_digest, "다이제스트가 메일에 실려서는 안 된다"
      assert_not_includes body, @teacher.password_salt, "salt 가 메일에 실려서는 안 된다"
    end
  end

  test "email_verification renders both parts with the token link and expiry" do
    mail = AccountMailer.email_verification(@teacher, "VERIFY456")
    expected = ApplicationController.helpers.duration_ko(User::EMAIL_VERIFICATION_EXPIRY)

    assert_equal "[책갈피] 이메일 주소 확인 안내", mail.subject
    parts_of(mail).each do |body|
      assert_includes body, "VERIFY456"
      assert_includes body, expected
    end
  end

  test "links point at the configured app host" do
    mail = AccountMailer.password_reset(@teacher, "TOKEN123")
    host = Rails.application.config.action_mailer.default_url_options[:host]

    assert_includes mail.html_part.body.to_s, host
  end

  private

  # 멀티파트(html + text) 두 본문. 한쪽만 렌더되면 여기서 바로 실패한다.
  def parts_of(mail)
    assert mail.html_part.present?, "HTML 파트가 있어야 한다"
    assert mail.text_part.present?, "텍스트 파트가 있어야 한다"

    [ mail.html_part.body.to_s, mail.text_part.body.to_s ]
  end
end
