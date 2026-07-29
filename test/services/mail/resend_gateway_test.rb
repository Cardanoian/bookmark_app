require "test_helper"

# Resend 발송 설정의 단일 진실(키 소스·가용성·발신주소·실패 분류).
class Mail::ResendGatewayTest < ActiveSupport::TestCase
  test "test credentials stub leaves the gateway unavailable by default" do
    assert_not Mail::ResendGateway.available?,
               "테스트는 실 키로 외부 발송을 시도하지 않아야 한다(test_helper 의 credentials 스텁)"
  end

  test "ENV takes priority over credentials" do
    with_mail_delivery_available do
      assert Mail::ResendGateway.available?
      assert_equal "re_test_only_not_a_real_key", Mail::ResendGateway.api_key
    end
  end

  test "from_address defaults to the verified sender and honours the ENV override" do
    assert_equal "책갈피 <admin@chaekgalpi.net>", Mail::ResendGateway.from_address

    original = ENV["MAIL_FROM"]
    ENV["MAIL_FROM"] = "other@example.com"
    assert_equal "other@example.com", Mail::ResendGateway.from_address
  ensure
    ENV["MAIL_FROM"] = original
  end

  # 실패 분류는 감사 로그 라벨용이다 — 분류가 틀려도 폴백 동작은 같아야 하고,
  # 여기서 검증하는 것은 라벨이 의도대로 갈리는지뿐이다.
  test "classify labels an unverified domain error" do
    error = Resend::Error.new("The domain is not verified.", nil)

    assert_equal :domain_unverified, Mail::ResendGateway.classify(error)
  end

  test "classify labels a rate limit error" do
    error = Resend::Error::RateLimitExceededError.new("Too many requests", nil)

    assert_equal :quota, Mail::ResendGateway.classify(error)
  end

  test "classify falls back to unknown for anything else" do
    assert_equal :unknown, Mail::ResendGateway.classify(Resend::Error.new("Invalid API key", nil))
    assert_equal :unknown, Mail::ResendGateway.classify(StandardError.new("boom"))
  end
end
