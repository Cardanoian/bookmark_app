require "test_helper"

class PrivacyPoliciesHelperTest < ActionView::TestCase
  # 컨트롤러(turbo-rails)가 뷰에 넘기는 helper_method — 여기서는 웹 요청으로 둔다. 앱 분기는 통합 테스트가 본다.
  def hotwire_native_app? = false

  test "inline formatting escapes everything except bold, https links and table line breaks" do
    html = policy_inline("**굵게** <script>x</script> [안내](https://example.com/a) 다음<br>줄")

    assert_equal '<strong class="font-semibold text-ink">굵게</strong> &lt;script&gt;x&lt;/script&gt; ' \
                 '<a class="text-brand-blue underline" rel="noopener noreferrer" target="_blank" href="https://example.com/a">안내</a> 다음<br>줄',
                 html
  end

  test "links with other schemes stay as plain text" do
    html = policy_inline("[누르기](javascript:alert(1))")

    assert_not_includes html, "<a"
    assert_equal "[누르기](javascript:alert(1))", html

    # http 는 앱(TrustedUrlPolicy)이 거부해 앱에서 죽은 링크가 되므로 링크로 만들지 않는다.
    assert_equal "[안내](http://example.com)", policy_inline("[안내](http://example.com)")
  end
end
