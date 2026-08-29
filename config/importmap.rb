# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Hotwire Native 앱 전용 브리지. **자체 호스팅**(vendor/javascript)이라 CSP 의 script-src :self 를
# 유지한 채 쓴다 — 외부 CDN 을 추가하면 초등 대상 서비스의 네트워크 표면이 넓어진다.
# 웹 브라우저에서는 BridgeComponent.shouldLoad 가 false 라 Stimulus 가 컨트롤러를 붙이지 않으므로,
# 이 핀이 있어도 웹 동작은 변하지 않는다(UA 에 `bridge-components: [...]` 가 없다).
pin "@hotwired/hotwire-native-bridge", to: "@hotwired--hotwire-native-bridge.js" # @1.2.2
