import { Controller } from "@hotwired/stimulus"

// 새 독후감 1스텝(책 고르기)의 진행 게이트. `book_search` 가 dispatch 하는 book:selected /
// book:deselected 를 구독해 "다음" 버튼을 열고 닫는다.
//
// 왜 필요한가: 검색 input 과 "다음" submit 이 같은 GET 폼에 있어서, 책을 고르지 않아도 입력한
// 자유 텍스트만으로 다음 단계에 도달할 수 있었다. 엔터 경로는 book_search#submitSearch 가 막고,
// 클릭 경로를 여기서 막는다.
//
// 자유 제목 폴백은 없애지 않는다 — 카탈로그·네이버에 없는 책도 독후감을 쓸 수 있어야 한다
// (`_book_chooser` 의 mode: "fallback" 은 의도된 설계다). 다만 **명시적으로** 눌러야 한다.
//
// 그레이스풀: 서버는 두 버튼을 활성 상태로 렌더하고 connect() 에서 비활성화한다. JS 가 없으면
// 지금까지와 똑같이 동작한다(report_guide 가 폼을 숨기는 것과 같은 관용구).
export default class extends Controller {
  static targets = ["next", "fallback", "input"]

  connect() {
    this.refresh()
  }

  // 목록에서 책을 고름 — 로컬은 book_id, 원격(네이버)은 isbn 이 채워진다. 어느 쪽이든 "선택"이다.
  selected() {
    this.selectedBook = true
    this.refresh()
  }

  // 입력이 바뀌어 직전 선택이 무효가 됨.
  deselected() {
    this.selectedBook = false
    this.refresh()
  }

  // 자유 제목 버튼은 "무언가 입력했는가"로만 갈린다(선택 여부와 무관).
  typed() {
    this.refresh()
  }

  refresh() {
    this.toggle(this.hasNextTarget ? this.nextTarget : null, this.selectedBook === true)
    this.toggle(this.hasFallbackTarget ? this.fallbackTarget : null, this.hasTypedTitle())
  }

  hasTypedTitle() {
    return this.hasInputTarget && this.inputTarget.value.trim().length > 0
  }

  toggle(element, enabled) {
    if (!element) return

    element.disabled = !enabled
    element.classList.toggle("opacity-50", !enabled)
    element.classList.toggle("cursor-not-allowed", !enabled)
  }
}
