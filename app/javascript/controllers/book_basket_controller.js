import { Controller } from "@hotwired/stimulus"

// 목표별 '여러 책' 지정 바스켓(미션·챌린지 목표 폼). 중첩된 book-search 가 dispatch 하는
// `book:selected` 이벤트를 받아 선택한 책을 칩으로 누적한다. 로컬(카탈로그) 책은 hidden `[ids][]`
// 배열에, 원격(네이버 "🔍 검색") 책은 hidden `[isbns][]` 배열에 담는다(서버가 제출 시 등록·중복 제거).
// 칩의 × 로 개별 제거하고, 같은 책 중복 추가는 무시한다. JS 미로딩 시엔 서버가 프리필한 칩(기존 지정
// 도서)만 남아 선택이 보존된다(그레이스풀).
export default class extends Controller {
  static targets = ["chips"]
  static values = { idsName: String, isbnsName: String }

  // book:selected 수신. 로컬(id 보유)이면 ids 배열, 원격(id 없음+isbn)이면 isbns 배열에 칩을 추가한다.
  add(event) {
    const detail = event.detail || {}
    const id = detail.id != null && detail.id !== "" ? String(detail.id) : null
    const isbn = detail.isbn != null && detail.isbn !== "" ? String(detail.isbn) : null
    const key = id ? `id:${id}` : (isbn ? `isbn:${isbn}` : null)
    if (!key) return

    this.resetInput()
    if (this.chipsTarget.querySelector(`[data-key="${CSS.escape(key)}"]`)) return // 중복 무시

    const name = id ? this.idsNameValue : this.isbnsNameValue
    const value = id || isbn
    this.chipsTarget.append(this.chip(key, detail.title || value, name, value))
  }

  remove(event) {
    const chip = event.currentTarget.closest("[data-key]")
    if (chip) chip.remove()
  }

  chip(key, label, name, value) {
    const span = document.createElement("span")
    span.className = "badge badge-neutral inline-flex items-center gap-1"
    span.dataset.key = key

    const text = document.createElement("span")
    text.textContent = label

    const hidden = document.createElement("input")
    hidden.type = "hidden"
    hidden.name = name
    hidden.value = value

    const btn = document.createElement("button")
    btn.type = "button"
    btn.textContent = "×"
    btn.className = "leading-none text-steel hover:text-ink"
    btn.setAttribute("aria-label", "제거")
    btn.dataset.action = "book-basket#remove"

    span.append(text, hidden, btn)
    return span
  }

  // 추가 후 검색 입력과 결과 목록을 비워 다음 책을 이어서 검색할 수 있게 한다.
  resetInput() {
    const input = this.element.querySelector('[data-book-search-target="input"]')
    if (input) input.value = ""
    const results = this.element.querySelector('[data-book-search-target="results"]')
    if (results) {
      results.replaceChildren()
      results.classList.add("hidden")
    }
  }
}
