import { Controller } from "@hotwired/stimulus"

// 버튼 하나로 패널을 여닫는 최소 공개(disclosure) 컨트롤러.
// <details>/<summary> 를 대신한다 — summary 를 다른 버튼과 같은 줄에 두면 열린 내용까지
// 그 줄 안으로 끌려들어와 레이아웃이 무너지는데, 이 컨트롤러는 버튼(toggle)과 내용(panel)을
// 떼어 놓을 수 있다.
//
// JS 가 로드되지 않으면 패널은 마크업 그대로 펼쳐진 채 남는다(내용을 잃지 않는다).
// 접는 일은 connect 에서만 한다 — report_guide 와 같은 그레이스풀 디그레이데이션 패턴.
export default class extends Controller {
  static targets = ["panel", "toggle"]

  connect() {
    this.expanded = false
  }

  toggle() {
    this.expanded = this.panelTarget.hidden
  }

  set expanded(value) {
    this.panelTarget.hidden = !value
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", String(value))
  }
}
