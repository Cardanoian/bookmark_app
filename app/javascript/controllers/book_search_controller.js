import { Controller } from "@hotwired/stimulus"

// /books/search 자동완성(디바운스). 입력을 서버 SearchService 로 보내 결과를 목록으로 렌더한다. (P5.1)
export default class extends Controller {
  static targets = ["input", "results"]
  static values = {
    url: { type: String, default: "/books/search" },
    delay: { type: Number, default: 300 }
  }

  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.fetchResults(), this.delayValue)
  }

  async fetchResults() {
    const query = this.inputTarget.value.trim()
    if (query.length < 2) {
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

    this.resultsTarget.innerHTML = items.map((item) => this.itemHtml(item)).join("")
    this.resultsTarget.classList.remove("hidden")
  }

  itemHtml(item) {
    const title = this.escape(item.title)
    const meta = this.escape([item.author, item.publisher].filter(Boolean).join(" · "))
    return `<li class="border-b border-gray-100 px-3 py-2 text-sm last:border-b-0">
      <span class="font-medium text-gray-900">${title}</span>
      <span class="text-gray-400">${meta}</span>
    </li>`
  }

  escape(value) {
    const holder = document.createElement("div")
    holder.textContent = value == null ? "" : String(value)
    return holder.innerHTML
  }

  clear() {
    if (!this.hasResultsTarget) return
    this.resultsTarget.innerHTML = ""
    this.resultsTarget.classList.add("hidden")
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
