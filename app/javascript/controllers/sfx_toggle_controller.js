import { Controller } from "@hotwired/stimulus"
import { isMuted, setMuted, play } from "sfx"

// 학생 헤더의 소리 켜기/끄기 버튼. 상태는 기기 단위(localStorage)로 기억한다.
// JS 가 없으면 버튼이 의미 없으므로 hidden 클래스로 렌더하고 여기서 드러낸다.
export default class extends Controller {
  static targets = ["on", "off"]

  connect() {
    this.element.classList.remove("hidden")
    this.sync()
  }

  toggle() {
    const muted = !isMuted()
    setMuted(muted)
    this.sync()
    if (!muted) play("reward")
  }

  sync() {
    const muted = isMuted()
    this.element.setAttribute("aria-pressed", String(!muted))
    this.element.setAttribute("aria-label", muted ? "소리 켜기" : "소리 끄기")
    this.element.title = muted ? "소리 켜기" : "소리 끄기"
    if (this.hasOnTarget) this.onTarget.classList.toggle("hidden", muted)
    if (this.hasOffTarget) this.offTarget.classList.toggle("hidden", !muted)
  }
}
