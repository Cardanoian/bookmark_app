import { Controller } from "@hotwired/stimulus"

// NEIS 생기부 요약 등 텍스트를 클립보드로 복사한다.
export default class extends Controller {
  static targets = ["source", "button"]

  copy() {
    const text = this.sourceTarget.value
    const done = () => this.flash()

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, () => this.fallbackCopy(text, done))
    } else {
      this.fallbackCopy(text, done)
    }
  }

  fallbackCopy(text, done) {
    this.sourceTarget.focus()
    this.sourceTarget.select()
    document.execCommand("copy")
    done()
  }

  flash() {
    if (!this.hasButtonTarget) return

    const label = this.buttonTarget.textContent
    this.buttonTarget.textContent = "복사됨"
    setTimeout(() => { this.buttonTarget.textContent = label }, 1500)
  }
}
