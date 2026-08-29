import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// 인쇄 버튼을 Android 시스템 인쇄(및 PDF 로 저장)에 연결한다(Android 계획 §7.5).
//
// **일반 브라우저에서는 이 컨트롤러가 아예 로드되지 않으므로** 버튼의 인라인 `window.print()`
// 폴백이 그대로 동작한다. 앱에서는 WebView 의 `window.print()` 가 아무 일도 하지 않으므로,
// 연결되는 즉시 그 폴백을 걷어내 인쇄 경로를 하나로 만든다(버튼을 눌러도 반응 없는 상태 방지).
export default class extends BridgeComponent {
  static component = "print"

  connect() {
    super.connect()
    this.element.removeAttribute("onclick")
  }

  print(event) {
    event.preventDefault()
    this.send("print")
  }
}
