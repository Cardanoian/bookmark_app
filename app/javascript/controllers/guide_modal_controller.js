import { Controller } from "@hotwired/stimulus"

// 사진으로 쓰기 전 자가점검 가이드(_photo_guide)를 모달로 승격한다. JS 미로딩 시엔 패널이
// 그냥 보이는 카드로 남아 완전 동작한다(그레이스풀). 연결되면 화면 중앙 오버레이로 승격하고
// 최초 진입에 자동으로 열어 보여 준다. Esc/배경 클릭으로 닫고, "작성 팁 다시 보기" 버튼으로
// 다시 열 수 있다.
export default class extends Controller {
  static targets = ["panel", "overlay", "confirm"]

  connect() {
    this.onKeydown = this.onKeydown.bind(this)
    this.reset = this.reset.bind(this)
    document.addEventListener("keydown", this.onKeydown)
    document.addEventListener("turbo:before-cache", this.reset)

    this.promote()
    this.open()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("turbo:before-cache", this.reset)
    document.body.classList.remove("overflow-hidden")
  }

  get overlayPromotedClasses() {
    return ["fixed", "inset-0", "z-[60]", "bg-black/50"]
  }

  get panelPromotedClasses() {
    return [
      "fixed", "inset-x-4", "top-1/2", "z-[61]", "-translate-y-1/2",
      "mx-auto", "max-w-md", "max-h-[85vh]", "overflow-y-auto"
    ]
  }

  // 패널·오버레이를 화면 중앙 고정 스타일로 승격한다(JS 있을 때만 모달처럼 보이게).
  promote() {
    if (this.hasOverlayTarget) this.overlayTarget.classList.add(...this.overlayPromotedClasses)
    if (this.hasPanelTarget) this.panelTarget.classList.add(...this.panelPromotedClasses)
  }

  // 승격 클래스를 걷어 비-모달 카드 레이아웃으로 되돌린다(캐시 스냅샷·재연결 전 정리).
  demote() {
    if (this.hasOverlayTarget) this.overlayTarget.classList.remove(...this.overlayPromotedClasses)
    if (this.hasPanelTarget) this.panelTarget.classList.remove(...this.panelPromotedClasses)
  }

  open() {
    // 닫을 때 포커스를 되돌리기 위해 현재 포커스 요소를 기억한다(a11y — 스크린리더/키보드).
    this.previouslyFocused = document.activeElement
    if (this.hasOverlayTarget) this.overlayTarget.classList.remove("hidden")
    if (this.hasPanelTarget) {
      this.panelTarget.classList.remove("hidden")
      this.panelTarget.setAttribute("aria-modal", "true")
    }
    document.body.classList.add("overflow-hidden")
    if (this.hasConfirmTarget) this.confirmTarget.focus()
  }

  close() {
    if (this.hasOverlayTarget) this.overlayTarget.classList.add("hidden")
    if (this.hasPanelTarget) {
      this.panelTarget.classList.add("hidden")
      this.panelTarget.removeAttribute("aria-modal")
    }
    document.body.classList.remove("overflow-hidden")
    this.restoreFocus()
  }

  // 모달을 닫으면 열기 전 포커스로 되돌려 키보드/스크린리더 사용자가 흐름을 잃지 않게 한다.
  restoreFocus() {
    const el = this.previouslyFocused
    this.previouslyFocused = null
    if (el && typeof el.focus === "function" && document.contains(el)) el.focus()
  }

  onKeydown(event) {
    if (event.key !== "Escape") return
    if (this.hasPanelTarget && this.panelTarget.classList.contains("hidden")) return

    this.close()
  }

  // turbo:before-cache — 캐시될 스냅샷을 "패널 보임 + 오버레이 숨김 + 승격 클래스 제거"(비-모달
  // 기본 카드)로 되돌려, bfcache 복원 시 배경 없는 고정 패널이 뜬 채로 굳지 않고 재방문마다 일관되게 만든다.
  reset() {
    if (this.hasOverlayTarget) this.overlayTarget.classList.add("hidden")
    this.demote()
    if (this.hasPanelTarget) {
      this.panelTarget.classList.remove("hidden")
      this.panelTarget.removeAttribute("aria-modal")
    }
    document.body.classList.remove("overflow-hidden")
  }
}
