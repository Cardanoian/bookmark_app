import { Controller } from "@hotwired/stimulus"

// 고쳐쓰기(수정) 폼: 본문이 원본과 실제로 달라졌을 때만 "수정하기" 버튼을 활성화한다.
// resubmit? 가드(본문 변경 시에만 재첨삭)와 짝을 이뤄, 바뀐 게 없는데 저장을 눌러
// "왜 재첨삭이 안 되지?" 하는 혼란을 없앤다. JS 미로딩 시엔 버튼이 그대로 활성(그레이스풀).
export default class extends Controller {
  static targets = ["body", "submit"]

  connect() {
    this.refresh()
  }

  // 최초 본문을 기준값으로 기록한다. OCR 초안 등으로 textarea 가 통째로 교체돼도
  // 기준값은 유지되어, 교체된 새 본문은 "변경됨"으로 간주된다.
  bodyTargetConnected() {
    if (this.initialBody === undefined) {
      this.initialBody = this.bodyTarget.value
    }
    this.refresh()
  }

  refresh() {
    if (!this.hasBodyTarget || !this.hasSubmitTarget) return
    if (this.initialBody === undefined) this.initialBody = this.bodyTarget.value

    const changed = this.bodyTarget.value !== this.initialBody
    this.submitTarget.disabled = !changed
    this.submitTarget.classList.toggle("opacity-50", !changed)
    this.submitTarget.classList.toggle("cursor-not-allowed", !changed)
  }
}
