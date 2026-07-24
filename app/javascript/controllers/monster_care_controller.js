import { Controller } from "@hotwired/stimulus"

// 먹이/진화 연출 트리거. 진화·먹이주기 직후 스프라이트를 잠깐 통통 튀게 한다. (P4.7)
// 의존성 없이 CSS 애니메이션 클래스만 토글.
export default class extends Controller {
  static targets = ["sprite"]
  static values = { celebrate: Boolean }

  connect() {
    if (this.celebrateValue) this.celebrate()
  }

  celebrate() {
    if (!this.hasSpriteTarget) return

    this.spriteTarget.classList.add("animate-bounce")
    setTimeout(() => this.spriteTarget.classList.remove("animate-bounce"), 1200)
  }
}
