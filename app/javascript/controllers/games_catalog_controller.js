import { Controller } from "@hotwired/stimulus"

// 게임 카탈로그(WS-C) — 폼리스 도서 검색으로 책을 고르면(book-search 가 dispatch 하는 book:selected)
// 5종 게임 칩을 그 book_id 로 진입하도록 활성화한다. 선택 전에는 칩이 비활성(클릭 불가)으로 안내만 한다.
export default class extends Controller {
  static targets = ["chip", "hint"]

  connect() {
    this.disableChips()
  }

  // 책 선택 전 상태 — 링크로 동작하지 않게 href 를 비우고 비활성 스타일을 건다.
  disableChips() {
    this.chipTargets.forEach((chip) => {
      chip.removeAttribute("href")
      chip.setAttribute("aria-disabled", "true")
      chip.classList.add("pointer-events-none", "opacity-50")
    })
  }

  // book:selected 수신 — 각 칩을 선택한 책의 play 경로(?book_id=)로 링크·활성화한다.
  bookSelected(event) {
    const bookId = event.detail && event.detail.id
    if (!bookId) return

    this.chipTargets.forEach((chip) => {
      chip.href = `${chip.dataset.playPath}?book_id=${encodeURIComponent(bookId)}`
      chip.removeAttribute("aria-disabled")
      chip.classList.remove("pointer-events-none", "opacity-50")
    })

    if (this.hasHintTarget) {
      const title = event.detail.title
      this.hintTarget.textContent = title
        ? `‘${title}’(으)로 원하는 게임을 시작해 보세요.`
        : "원하는 게임을 시작해 보세요."
    }
  }
}
