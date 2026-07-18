import { Controller } from "@hotwired/stimulus"

// 도서 자동완성(디바운스). 입력을 서버(SearchService/로컬 카탈로그)로 보내 결과를 목록으로
// 렌더하고, 항목 선택 시 (a)hidden book_id (b)표시 input title (c)표지 img 를 채운 뒤
// `book:selected` 커스텀 이벤트를 dispatch 한다. bookId·cover 타깃은 선택적(hasXTarget 가드)이라
// hidden 없이 이벤트만 소비하는 화면(게임)도 지원한다. (P5.1 / 공용 자동완성 계약)
//
// mode: "fallback"(미선택 자유텍스트 허용) | "strict"(목록 선택만 유효 — 편집 시 book_id 무효화로
// 서버 폼이 미선택을 거른다). url 기본값은 카탈로그 검색(/books/search)이라 기존 화면은 무변경.
export default class extends Controller {
  static targets = ["input", "results", "bookId", "cover"]
  static values = {
    url: { type: String, default: "/books/search" },
    mode: { type: String, default: "fallback" },
    minChars: { type: Number, default: 2 },
    delay: { type: Number, default: 300 }
  }

  search() {
    // 입력이 바뀌면 직전 선택은 더 이상 유효하지 않으므로 book_id 를 무효화한다.
    if (this.hasBookIdTarget) this.bookIdTarget.value = ""
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.fetchResults(), this.delayValue)
  }

  async fetchResults() {
    const query = this.inputTarget.value.trim()
    if (query.length < this.minCharsValue) {
      this.clear()
      return
    }

    try {
      const url = `${this.urlValue}?q=${encodeURIComponent(query)}`
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) {
        this.clear()
        return
      }
      this.render(await response.json())
    } catch (_error) {
      this.clear()
    }
  }

  render(items) {
    if (!this.hasResultsTarget) return
    if (!Array.isArray(items) || items.length === 0) {
      this.clear()
      return
    }

    this.resultsTarget.replaceChildren(...items.map((item) => this.itemElement(item)))
    this.resultsTarget.classList.remove("hidden")
  }

  // 결과 항목 <li>. 클릭/Enter 로 선택되며, id·title·표지를 data-* 로 실어 select 가 읽는다.
  itemElement(item) {
    const title = item.title == null ? "" : String(item.title)
    const cover = item.cover_url || item.cover || item.thumbnail || ""

    const li = document.createElement("li")
    li.className = "cursor-pointer border-b border-gray-100 px-3 py-2 text-sm last:border-b-0 hover:bg-gray-50"
    li.tabIndex = 0
    li.dataset.action = "click->book-search#select keydown.enter->book-search#select"
    if (item.id != null) li.dataset.bookId = String(item.id)
    li.dataset.bookTitle = title
    if (cover) li.dataset.bookCover = String(cover)

    const titleEl = document.createElement("span")
    titleEl.className = "font-medium text-gray-900"
    titleEl.textContent = title

    const metaEl = document.createElement("span")
    metaEl.className = "text-gray-400"
    const meta = [item.author, item.publisher].filter(Boolean).join(" · ")
    metaEl.textContent = meta ? ` ${meta}` : ""

    li.append(titleEl, metaEl)
    return li
  }

  // 항목 선택: hidden book_id·표시 input·표지 img 를 채우고 book:selected 를 dispatch.
  select(event) {
    const data = event.currentTarget.dataset
    const id = data.bookId != null && data.bookId !== "" ? data.bookId : null
    const title = data.bookTitle || ""
    const cover = data.bookCover || ""

    if (this.hasBookIdTarget) this.bookIdTarget.value = id == null ? "" : id
    this.inputTarget.value = title
    if (this.hasCoverTarget && cover) {
      this.coverTarget.src = cover
      this.coverTarget.classList.remove("hidden")
    }

    this.dispatch("selected", { prefix: "book", detail: { id, title, cover } })
    this.clear()
  }

  clear() {
    if (!this.hasResultsTarget) return
    this.resultsTarget.replaceChildren()
    this.resultsTarget.classList.add("hidden")
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
