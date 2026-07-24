import { Controller } from "@hotwired/stimulus"

// 학생 메뉴의 모바일 disclosure를 보조한다. 열기/닫기 자체는 네이티브
// details/summary가 담당하고, 이 컨트롤러는 일반적인 메뉴 닫힘 동작과
// Turbo snapshot에 열린 상태가 남지 않도록 하는 역할만 맡는다.
export default class extends Controller {
  static targets = ["menu", "summary"]

  close(event) {
    if (!this.hasMenuTarget || !this.menuTarget.open) return

    this.menuTarget.open = false
    if (event?.type === "keydown" && this.hasSummaryTarget) this.summaryTarget.focus()
  }

  closeFromOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }
}
