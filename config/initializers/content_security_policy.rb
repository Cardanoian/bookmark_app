# Be sure to restart your server when you modify this file.

# 애플리케이션 전역 Content-Security-Policy(§2.9). XSS(스크립트 인젝션) 방어를 위해
# 리소스를 자기 출처(:self)로 제한한다. 이 앱은 importmap-rails + turbo/stimulus +
# tailwindcss-rails 를 모두 자체 호스팅하므로 외부 CDN 출처가 필요 없다.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri    :self
    policy.form_action :self
    policy.object_src  :none

    # importmap 이 생성하는 인라인 <script type="importmap"> · 모듈 스크립트는 아래
    # nonce 로 허용된다(자체 호스팅 JS 는 :self). 'unsafe-hashes' + 해시는 인쇄
    # 레이아웃(app/views/layouts/print.html.erb)의 유일한 인라인 핸들러
    # onclick="window.print()" 하나만 정확히 허용하기 위한 것으로, 다른 인라인
    # 스크립트는 계속 차단된다. (핸들러 텍스트가 바뀌면 해시도 갱신해야 함.)
    policy.script_src  :self,
                       "'unsafe-hashes'",
                       "'sha256-MguIPR6qNR8D3B+eAlK+bIRTZe8t3wkOY4B/56Me9FU='"

    # tailwind 컴파일 스타일시트는 :self. 진행바 등 동적 width(style="") 인라인
    # 속성과 인쇄 레이아웃의 <style> 블록을 위해 unsafe-inline 을 허용한다.
    # (인라인 style 속성은 nonce 로 대체 불가하므로 style-src 는 nonce 미적용.)
    policy.style_src   :self, :unsafe_inline

    # 이미지: 자체 호스팅(:self) + 인라인 data: 외에, 네이버 도서 API 가 주는 외부
    # 표지 URL(book.cover_url, https)과 사진 업로드 미리보기의 createObjectURL(blob:)
    # 을 허용해야 표지·OCR 미리보기·클라이언트 압축이 브라우저에서 정상 동작한다.
    policy.img_src     :self, :data, :blob, :https
    policy.font_src    :self, :data
    # 실시간 갱신(Turbo Streams/Action Cable)은 동일 출처 /cable 웹소켓을 쓴다.
    # CSP3 브라우저는 :self 로 동일 출처 ws/wss 업그레이드를 허용한다. 구형(CSP2)
    # 기기가 대상이면 실기기에서 /cable 연결을 검증할 것(후속 과제).
    policy.connect_src :self
  end

  # importmap·인라인 스크립트에 요청별 nonce 를 주입한다. style-src 는 위
  # unsafe-inline 을 유지해야 하므로 nonce 대상에서 제외한다(nonce 존재 시
  # 브라우저가 unsafe-inline 을 무시해 인라인 style 속성이 깨진다).
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
