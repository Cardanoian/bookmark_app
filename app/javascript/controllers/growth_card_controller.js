import { Controller } from "@hotwired/stimulus"

// 성장카드 PNG 내보내기(P6.3). data-* 값으로 학생 성장 요약을 Canvas 에 그리고,
// 버튼으로 PNG 를 내려받는다. 서버 렌더 SVG 와 별개인 클라이언트 전용 기능.
export default class extends Controller {
  static targets = ["canvas"]
  static values = { name: String, avg: String, level: String, reports: String }

  connect() {
    if (this.hasCanvasTarget) this.draw()
  }

  draw() {
    const canvas = this.canvasTarget
    const ctx = canvas.getContext("2d")
    if (!ctx) return

    ctx.fillStyle = "#ffffff"
    ctx.fillRect(0, 0, canvas.width, canvas.height)
    ctx.fillStyle = "#facc15"
    ctx.fillRect(0, 0, canvas.width, 12)

    ctx.fillStyle = "#111827"
    ctx.font = "bold 28px sans-serif"
    ctx.fillText("독서 성장 카드", 32, 72)

    ctx.font = "22px sans-serif"
    ctx.fillText(this.nameValue || "", 32, 120)

    ctx.font = "18px sans-serif"
    ctx.fillStyle = "#4b5563"
    ctx.fillText(`평균 ${this.avgValue || "-"} · 등급 ${this.levelValue || "-"}`, 32, 160)
    ctx.fillText(`독후감 ${this.reportsValue || "0"}편`, 32, 190)
  }

  download() {
    if (!this.hasCanvasTarget) return
    // Android 앱에서는 save-image 브리지가 같은 버튼에 물려 저장을 맡는다. WebView 에서
    // `<a download>` + data URL 은 아무 일도 하지 않으므로 두 경로가 겹치지 않게 여기서 물러난다.
    if (this.nativeSaveAvailable) return

    const link = document.createElement("a")
    link.download = `growth_card_${this.nameValue || "student"}.png`
    link.href = this.canvasTarget.toDataURL("image/png")
    link.click()
  }

  // 브리지 어댑터가 `<html data-bridge-components="...">` 에 지원 컴포넌트를 적어 둔다.
  // 이 속성이 없으면(= 일반 브라우저) 기존 다운로드 경로를 그대로 쓴다.
  get nativeSaveAvailable() {
    const components = document.documentElement.dataset.bridgeComponents
    return !!components && components.split(" ").includes("save-image")
  }
}
