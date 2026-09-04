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
//
// [시리즈 접기 2단계] 로컬 자동완성(/books/autocomplete)이 series_count>1 인 시리즈 대표행을 실어
// 오면, 그 항목은 "전 N권" 배지를 달고 클릭 시 즉시 선택하지 않고 volumesUrl(/books/volumes)로 권
// 목록을 fetch 해 드릴다운(권 선택 단계 + "← 뒤로")으로 교체한다. 특정 권을 고르면 그 권의 book_id
// 로 확정 선택된다(단권·원격 결과는 series_count 가 없어 기존처럼 즉시 선택 — 하위호환).
export default class extends Controller {
  static targets = ["input", "results", "bookId", "cover", "searchButton", "isbn"]
  static values = {
    url: { type: String, default: "/books/search" },
    remoteSearchUrl: { type: String, default: "" },
    volumesUrl: { type: String, default: "/books/volumes" },
    mode: { type: String, default: "fallback" },
    minChars: { type: Number, default: 2 },
    delay: { type: Number, default: 300 }
  }

  search() {
    // 입력이 바뀌면 직전 선택은 더 이상 유효하지 않으므로 book_id 를 무효화한다.
    if (this.hasBookIdTarget) this.bookIdTarget.value = ""
    // 원격(네이버) 선택은 book_id 가 아니라 isbn 에 스태시되므로 그것도 함께 비운다.
    if (this.hasIsbnTarget) this.isbnTarget.value = ""
    // **선택 해제를 알린다.** book:selected 만 있고 짝이 없으면, 구독자(예: 책 고르기의 "다음"
    // 버튼)는 한 번 활성화된 뒤 제목을 고쳐도 활성인 채 남아 미선택 자유텍스트가 그대로 통과한다.
    this.dispatch("deselected", { prefix: "book" })
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

  // 검색 입력에서 누른 엔터를 "폼 제출"이 아니라 "검색"으로 돌린다(opt-in — 파셜에
  // `block_enter_submit: true` 를 넘긴 화면에만 붙는다). 책 고르기 스텝은 검색 input 과 "다음"
  // submit 이 같은 폼에 있어서, 엔터 한 번이면 책을 고르지 않은 채 다음 단계로 넘어갔다.
  // 원격 검색이 켜진 화면이면 원격을, 아니면 로컬 자동완성을 즉시 조회한다(디바운스 대기 없이).
  submitSearch(event) {
    event.preventDefault()
    if (this.remoteSearchUrlValue) {
      this.manualSearch()
    } else {
      this.fetchResults()
    }
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

    // 드릴다운(권 선택)에서 "← 뒤로" 로 복귀할 수 있게 마지막 (접힌) 목록을 보관한다.
    this.lastResults = items
    this.resultsTarget.replaceChildren(...items.map((item) => this.itemElement(item)))
    this.resultsTarget.classList.remove("hidden")
  }

  // 결과 항목 <li> 디스패처. series_count>1 인 시리즈 대표는 배지+드릴다운, 그 외(단권·원격·개별 권)는
  // 클릭 즉시 선택되는 일반 항목으로 만든다.
  itemElement(item) {
    const seriesCount = Number(item.series_count) || 1
    return seriesCount > 1 ? this.seriesElement(item, seriesCount) : this.bookElement(item)
  }

  // 시리즈 대표 <li>. 클릭/Enter 로 선택하지 않고 drillIntoSeries(권 목록 fetch)로 진입하며,
  // "전 N권" 배지를 단다. 확정 선택은 권을 고른 뒤에 일어난다(strict 폼도 미선택으로 취급).
  seriesElement(item, seriesCount) {
    const title = item.title == null ? "" : String(item.title)

    const li = document.createElement("li")
    li.className = "cursor-pointer border-b border-gray-100 px-3 py-2 text-sm last:border-b-0 hover:bg-gray-50"
    li.tabIndex = 0
    li.dataset.action = "click->book-search#drillIntoSeries keydown.enter->book-search#drillIntoSeries"
    li.dataset.seriesTitle = title
    if (item.author != null) li.dataset.seriesAuthor = String(item.author)

    const titleEl = document.createElement("span")
    titleEl.className = "font-medium text-gray-900"
    titleEl.textContent = title

    const metaEl = document.createElement("span")
    metaEl.className = "text-gray-400"
    const meta = [item.author, item.publisher].filter(Boolean).join(" · ")
    metaEl.textContent = meta ? ` ${meta}` : ""

    li.append(titleEl, metaEl)

    const badgeRow = document.createElement("div")
    badgeRow.className = "mt-1 flex flex-wrap items-center gap-1"
    badgeRow.append(this.badge(`전 ${seriesCount}권`, "badge-neutral"), ...this.badgeElements(item))
    li.append(badgeRow)
    return li
  }

  // 일반 항목 <li>. 클릭/Enter 로 선택되며, id·title·표지·(원격이면)isbn 을 data-* 로 실어 select 가
  // 읽는다. 로컬 결과엔 id 가 있고 원격(네이버) 결과엔 id 대신 isbn 이 실려 온다. showVolume(드릴다운
  // 권 목록)이면 제목 앞에 "N권" 표식을 붙여 어느 권인지 구분한다(최상위 목록에선 붙이지 않는다).
  bookElement(item, { showVolume = false } = {}) {
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
    const volumeLabel = showVolume && item.volume != null ? `${item.volume}권 · ` : ""
    titleEl.textContent = `${volumeLabel}${title}`

    const metaEl = document.createElement("span")
    metaEl.className = "text-gray-400"
    const meta = [item.author, item.publisher].filter(Boolean).join(" · ")
    metaEl.textContent = meta ? ` ${meta}` : ""

    li.append(titleEl, metaEl)

    const badges = this.badgeElements(item)
    if (badges.length > 0) {
      const badgeRow = document.createElement("div")
      badgeRow.className = "mt-1 flex flex-wrap items-center gap-1"
      badgeRow.append(...badges)
      li.append(badgeRow)
    }
    return li
  }

  // 시리즈 대표 클릭 → volumesUrl 로 그 시리즈(제목+저자)의 전 권을 fetch 해 권 선택 단계로 교체한다.
  // 아직 확정 선택이 아니므로 book_id 를 비워 둔다(입력 편집과 동일하게 미선택 취급). 실패 시 현재
  // 목록을 유지한다(그레이스풀).
  async drillIntoSeries(event) {
    const data = event.currentTarget.dataset
    const title = data.seriesTitle || ""
    const author = data.seriesAuthor || ""
    if (this.hasBookIdTarget) this.bookIdTarget.value = ""

    try {
      const url = `${this.volumesUrlValue}?title=${encodeURIComponent(title)}&author=${encodeURIComponent(author)}`
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) return
      const volumes = await response.json()
      if (!Array.isArray(volumes) || volumes.length === 0) return
      this.renderVolumes(volumes, title)
    } catch (_error) {
      // 유지(그레이스풀)
    }
  }

  // 권 선택 단계. 상단에 "← 뒤로"(접힌 목록 복귀) 헤더 + 권 목록(각 항목은 클릭 시 그 권으로 확정 선택).
  renderVolumes(volumes, seriesTitle) {
    if (!this.hasResultsTarget) return

    const back = document.createElement("li")
    back.className = "cursor-pointer border-b border-gray-100 bg-gray-50 px-3 py-2 text-sm font-medium text-gray-600 hover:bg-gray-100"
    back.tabIndex = 0
    back.dataset.action = "click->book-search#backToResults keydown.enter->book-search#backToResults"
    back.textContent = `← ${seriesTitle} · 권 선택`

    const items = volumes.map((volume) => this.bookElement(volume, { showVolume: true }))
    this.resultsTarget.replaceChildren(back, ...items)
    this.resultsTarget.classList.remove("hidden")
  }

  // 권 목록에서 시리즈(접힌) 목록으로 복귀.
  backToResults() {
    if (this.lastResults) this.render(this.lastResults)
  }

  // 로컬(카탈로그) 결과의 고전 여부·장르 배지(서버 book_meta_badges 와 시각 일치).
  // 원격(네이버) 결과엔 genre/classic 필드가 없어 배지가 붙지 않는다(그레이스풀).
  badgeElements(item) {
    const badges = []
    if (item.classic) badges.push(this.badge("고전", "badge-yellow"))
    const genre = item.genre == null ? "" : String(item.genre).trim()
    if (genre && genre !== "미분류") badges.push(this.badge(genre, "badge-neutral"))
    return badges
  }

  badge(text, variant) {
    const span = document.createElement("span")
    span.className = `badge badge-sm ${variant}`
    span.textContent = text
    return span
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

    // isbn 은 원격(네이버) 선택에만 실려 온다(로컬은 null). 멀티북 바스켓이 원격 책을 구분해 등록 큐에
    // 담을 수 있도록 detail 에 함께 전달한다(기존 단일 선택 리스너는 추가 키를 무시 — 하위호환).
    this.dispatch("selected", { prefix: "book", detail: { id, title, cover, isbn } })
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
