module PrivacyPoliciesHelper
  # 굵게(**…**)와 외부 링크([글자](https://…)). 링크는 https 주소만 — 그 밖의 주소(javascript:·http: 등)는
  # 링크로 만들지 않고 글자 그대로 둔다. http 는 앱의 TrustedUrlPolicy 가 거부해 앱에서 죽은 링크가 된다.
  POLICY_INLINE_PATTERN = %r{\*\*(?<bold>.+?)\*\*|\[(?<label>[^\]]+)\]\((?<url>https://[^\s)]+)\)}

  # 처리방침 원본 한 줄의 인라인 서식을 그린다. 원본이 쓰는 것만 다룬다 — 굵게, 외부 링크, 표 칸 안
  # 줄바꿈(<br>). 나머지 글자는 모두 이스케이프한다(원본 문자열을 html_safe 로 내보내지 않는다).
  def policy_inline(text)
    safe_join(text.split(/<br\s*\/?>/i).map { |line| policy_inline_line(line) }, tag.br)
  end

  def policy_inline_line(line)
    parts = []
    rest = line
    while (match = POLICY_INLINE_PATTERN.match(rest))
      parts << match.pre_match
      parts << (match[:bold] ? tag.strong(match[:bold], class: "font-semibold text-ink") : policy_external_link(match[:label], match[:url]))
      rest = match.post_match
    end
    safe_join(parts << rest)
  end

  # 웹은 새 탭으로 연다. 앱(WebView)은 target="_blank" 를 무시해 링크가 죽으므로 target 없이 두고,
  # 바깥 호스트는 앱의 TrustedUrlPolicy 가 Custom Tab 으로 연다(reports/_ocr_photo 선례).
  def policy_external_link(label, url)
    options = { class: "text-brand-blue underline", rel: "noopener noreferrer" }
    options[:target] = "_blank" unless hotwire_native_app?
    link_to label, url, options
  end
end
