import { Controller } from "@hotwired/stimulus"

// 고쳐쓰기(수정) 폼: 본문이 원본과 실제로 달라졌을 때만 "수정하기" 버튼을 활성화한다.
// resubmit? 가드(본문 변경 시에만 재첨삭)와 짝을 이뤄, 바뀐 게 없는데 저장을 눌러
// "왜 재첨삭이 안 되지?" 하는 혼란을 없앤다. JS 미로딩 시엔 버튼이 그대로 활성(그레이스풀).
//
// 비교 기준은 둘 중 하나다.
// · baseline 값이 있으면(고쳐쓰기 초안) 그 값 — **원본 글의 본문**이다. 자동 저장이 고친 본문을
//   미리 저장해 두므로, 페이지를 연 순간의 본문을 기준으로 삼으면 다시 열었을 때 이미 고친 글인데도
//   버튼이 잠겨 선생님께 낼 수 없다. 서버 resubmit? 도 같은 기준(원본 대비)으로 판정한다.
// · 없으면 페이지를 연 순간의 본문(기존 동작).
export default class extends Controller {
  static targets = ["body", "submit"]
  static values = { baseline: String }

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

    const changed = this.hasBaselineValue
      ? normalize(this.bodyTarget.value) !== normalize(this.baselineValue)
      : this.bodyTarget.value !== this.initialBody
    this.submitTarget.disabled = !changed
    this.submitTarget.classList.toggle("opacity-50", !changed)
    this.submitTarget.classList.toggle("cursor-not-allowed", !changed)
  }
}

// 서버 resubmit? 의 normalized_body 와 같은 규칙: 줄바꿈(CRLF/LF) 차이와 앞뒤 공백은 고친 것으로 보지 않는다.
function normalize(text) {
  return text.replace(/\r\n?/g, "\n").trim()
}
