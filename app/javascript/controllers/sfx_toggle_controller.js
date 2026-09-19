import { Controller } from "@hotwired/stimulus"
import { isMuted, setMuted, play } from "sfx"

// 마이페이지 '효과음' 스위치(role="switch"). 상태는 기기 단위(localStorage)로 기억한다.
// 예전에는 학생 헤더에 있었으나, 좁은 화면에서 헤더 버튼이 넘쳐 가로 스크롤이 생기고 자주 바꾸는
// 설정도 아니어서 마이페이지로 옮겼다(2026-09-19). 이름은 aria-labelledby 가 주고, 여기서는 상태만 맞춘다.
// JS 가 없으면 스위치가 의미 없으므로 hidden 클래스로 렌더하고 여기서 드러낸다.
export default class extends Controller {
  static targets = ["on", "off", "label"]

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
    this.element.setAttribute("aria-checked", String(!muted))
    if (this.hasLabelTarget) this.labelTarget.textContent = muted ? "꺼짐" : "켜짐"
    if (this.hasOnTarget) this.onTarget.classList.toggle("hidden", muted)
    if (this.hasOffTarget) this.offTarget.classList.toggle("hidden", !muted)
  }
}
