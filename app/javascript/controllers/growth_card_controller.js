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

    const link = document.createElement("a")
    link.download = `growth_card_${this.nameValue || "student"}.png`
    link.href = this.canvasTarget.toDataURL("image/png")
    link.click()
  }
}
