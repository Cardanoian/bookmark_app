import { Controller } from "@hotwired/stimulus"

// 도서 자동완성(디바운스). 입력을 서버(SearchService/로컬 카탈로그)로 보내 결과를 목록으로
// 렌더하고, 항목 선택 시 (a)hidden book_id (b)표시 input title (c)표지 img 를 채운 뒤
// `book:selected` 커스텀 이벤트를 dispatch 한다. bookId·cover 타깃은 선택적(hasXTarget 가드)이라
// hidden 없이 이벤트만 소비하는 화면(게임)도 지원한다. (P5.1 / 공용 자동완성 계약)
//
// mode: "fallback"(미선택 자유텍스트 허용) | "strict"(목록 선택만 유효 — 편집 시 book_id 무효화로
// 서버 폼이 미선택을 거른다). url 기본값은 카탈로그 검색(/books/search)이라 기존 화면은 무변경.
//
// [opt-in 확장] remoteSearchUrl(빈 문자열=미설정)·searchButton·isbn 타깃이 있으면 "검색 버튼"으로
// 원격(네이버) 도서검색을 켤 수 있다(manualSearch). 원격 결과는 로컬 id 가 없고 isbn 을 실어 오며,
// 선택 시 book_id 대신 hidden isbn 에 스태시한다(등록은 제출 시 서버가 수행). 셋 다 미설정이면
// 기존 동작과 완전히 동일하다(하위호환). resolve/POST/async 없음 — select 는 동기 유지.
export default class extends Controller {
  static targets = ["input", "results", "bookId", "cover", "searchButton", "isbn"]
  static values = {
    url: { type: String, default: "/books/search" },
    remoteSearchUrl: { type: String, default: "" },
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

    await this.fetchInto(this.urlValue, query)
  }

  // 검색 버튼 클릭 시 원격(네이버) 도서검색. remoteSearchUrl 미설정이면 no-op(하위호환).
  // 사용자가 명시적으로 누른 것이라 minChars 를 강제하지 않고, 비어 있지만 않으면 조회한다.
  async manualSearch() {
    if (!this.remoteSearchUrlValue) return
    const query = this.inputTarget.value.trim()
    if (query.length === 0) {
      this.clear()
      return
    }

    await this.fetchInto(this.remoteSearchUrlValue, query)
  }

  // 공통 조회: 주어진 엔드포인트로 ?q= 를 fetch 해 결과 목록을 렌더한다(실패 시 clear).
  async fetchInto(endpoint, query) {
    try {
      const url = `${endpoint}?q=${encodeURIComponent(query)}`
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

  // 결과 항목 <li>. 클릭/Enter 로 선택되며, id·title·표지·(원격이면)isbn 을 data-* 로 실어 select 가
  // 읽는다. 로컬 결과엔 id 가 있고 원격(네이버) 결과엔 id 대신 isbn 이 실려 온다.
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
    if (item.isbn != null && item.isbn !== "") li.dataset.isbn = String(item.isbn)

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

  // 항목 선택: 로컬(카탈로그) 항목은 hidden book_id, 원격(네이버) 항목은 hidden isbn 에 연결하고
  // 표시 input·표지 img 를 채운 뒤 book:selected 를 dispatch(계약 불변: {id,title,cover}).
  select(event) {
    const data = event.currentTarget.dataset
    const id = data.bookId != null && data.bookId !== "" ? data.bookId : null
    const title = data.bookTitle || ""
    const cover = data.bookCover || ""
    const isbn = data.isbn != null && data.isbn !== "" ? data.isbn : null

    if (this.hasBookIdTarget) this.bookIdTarget.value = id == null ? "" : id
    if (this.hasIsbnTarget) {
      // 로컬 선택이면 직전 원격 isbn 스태시를 비우고, 원격(id 없음 + isbn) 선택이면 isbn 을 담는다.
      // 등록은 제출 시 서버가 수행하므로 여기선 book_id 를 만들지 않는다(동기·무통신).
      this.isbnTarget.value = id == null && isbn != null ? isbn : ""
    }

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
