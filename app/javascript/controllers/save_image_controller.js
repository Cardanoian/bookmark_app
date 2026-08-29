import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// 성장카드 PNG 를 네이티브 앱에 넘겨 사용자가 고른 위치에 저장한다(Android 계획 §7.4).
//
// **일반 브라우저에서는 이 컨트롤러가 아예 로드되지 않는다.** BridgeComponent.shouldLoad 가
// User-Agent 의 `bridge-components: [...]` 를 보고 판단하고, 앱만 그 문자열을 붙인다.
// 그래서 웹의 기존 `<a download>` 경로(growth-card#download)는 손대지 않아도 그대로 남는다.
export default class extends BridgeComponent {
  static component = "save-image"
  static targets = ["canvas"]
  static values = { filename: String }

  // Canvas data URL 은 base64 라 원본의 4/3 이다. 성장카드는 320×220 이라 실제로는 수 KB 지만,
  // 예상 밖으로 커진 payload 를 조용히 넘기지 않도록 웹에서도 상한을 둔다(네이티브도 같은 값으로 막는다).
  static MAX_BASE64_LENGTH = 512 * 1024

  save(event) {
    event.preventDefault()
    if (!this.hasCanvasTarget) return

    const base64 = this.canvasTarget.toDataURL("image/png").split(",")[1]
    if (!base64 || base64.length > this.constructor.MAX_BASE64_LENGTH) return

    this.send("save", { filename: this.filenameValue, base64 })
  }
}
