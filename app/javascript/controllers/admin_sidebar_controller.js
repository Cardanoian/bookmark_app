import { Controller } from "@hotwired/stimulus"

// 총괄관리자 콘솔 사이드바. 데스크톱(lg 이상)은 CSS(lg:)로 항상 노출되므로
// 이 컨트롤러는 태블릿/모바일의 오프캔버스 열기·닫기만 담당한다(그레이스풀:
// JS 미로딩 시에도 데스크톱 사이드바는 정상 동작).
export default class extends Controller {
  static targets = ["panel", "backdrop", "menuButton"]

  open() {
    this.panelTarget.classList.remove("-translate-x-full")
    this.panelTarget.classList.add("translate-x-0")
    this.backdropTarget.classList.remove("hidden")
    if (this.hasMenuButtonTarget) this.menuButtonTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.panelTarget.classList.remove("translate-x-0")
    this.panelTarget.classList.add("-translate-x-full")
    this.backdropTarget.classList.add("hidden")
    if (this.hasMenuButtonTarget) this.menuButtonTarget.setAttribute("aria-expanded", "false")
  }

  toggle() {
    if (this.panelTarget.classList.contains("-translate-x-full")) {
      this.open()
    } else {
      this.close()
    }
  }
}
