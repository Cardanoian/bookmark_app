import { Controller } from "@hotwired/stimulus"

// 학교 선택 하이브리드 피커(계획 §2.4). 시도(region)→시군구(gu) 캐스케이딩으로 학교 목록을
// 좁히고, 이름검색으로도 같은 결과를 채운다. 결과는 네이티브 <select> 옵션 교체가 아니라
// **클릭 가능한 목록형 드롭다운**(<li> 버튼)으로 렌더해, 입력 즉시 아래 목록에서 한 번의
// 클릭으로 학교를 고른다(select 를 다시 여닫는 조작 불필요). 선택 학교 id 는 hidden school
// 타깃에 담기고, gu 가 비거나 부정확한 학교도 이름검색으로 항상 도달 가능(graceful degrade).
// 로그인 폼(classroom 타깃 존재)이면 선택 학교의 학급만 스코프 조회해 종속 드롭다운을 채운다.
export default class extends Controller {
  static targets = ["region", "gu", "query", "school", "classroom", "results", "selected"]

  regionChanged() {
    const region = this.regionTarget.value
    this.resetSchool()
    if (!region) {
      this.setOptions(this.guTarget, [], "시군구 선택")
      this.guTarget.disabled = true
      return
    }
    this.fetchJson(`/schools/gus?region=${encodeURIComponent(region)}`).then((list) => {
      this.setOptions(this.guTarget, (list || []).map((gu) => ({ value: gu, label: gu })), "시군구 선택")
      this.guTarget.disabled = false
    })
  }

  guChanged() {
    const region = this.regionTarget.value
    const gu = this.guTarget.value
    this.resetSchool()
    if (!region || !gu) return

    const url = `/schools/search?region=${encodeURIComponent(region)}&gu=${encodeURIComponent(gu)}`
    this.fetchJson(url).then((schools) => this.fillSchools(schools))
  }

  searchByName() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.runNameSearch(), 300)
  }

  runNameSearch() {
    const query = this.queryTarget.value.trim()
    this.resetClassroom()
    if (query.length < 2) {
      this.clearResults()
      return
    }

    this.fetchJson(`/schools/search?q=${encodeURIComponent(query)}`).then((schools) => this.fillSchools(schools))
  }

  // <li> 버튼 클릭 = 학교 선택. hidden school 값·선택 표시를 세팅하고, 목록을 닫은 뒤
  // 기존 schoolChanged 로직을 재사용해 학급 캐스케이딩을 잇는다(로그인 폼일 때만).
  selectSchool(event) {
    const button = event.currentTarget
    this.schoolTarget.value = button.dataset.id || ""
    this.setSelected(button.textContent)
    this.clearResults()
    this.schoolChanged()
  }

  schoolChanged() {
    this.resetClassroom()
    const id = this.schoolTarget.value
    if (!id || !this.hasClassroomTarget) return

    this.fetchJson(`/schools/${encodeURIComponent(id)}/classrooms`).then((rooms) => {
      this.setOptions(this.classroomTarget, (rooms || []).map((room) => ({ value: room.id, label: room.label })), "학급 없음")
      this.classroomTarget.disabled = false
    })
  }

  // 검색·캐스케이딩 결과를 클릭 가능한 목록으로 렌더한다. 결과가 없으면 안내 항목만 보여 준다.
  fillSchools(schools) {
    if (!this.hasResultsTarget) return
    const list = schools || []
    if (!list.length) {
      this.resultsTarget.innerHTML = '<li class="px-3 py-2 text-sm text-steel">일치하는 학교가 없어요</li>'
      this.resultsTarget.hidden = false
      return
    }

    this.resultsTarget.innerHTML = list.map((school) => {
      const label = school.gu
        ? `${school.name} (${this.regionLabel(school.region)} ${school.gu})`
        : `${school.name} (${this.regionLabel(school.region)})`
      return `<li><button type="button"` +
        ` class="flex min-h-[2.75rem] w-full items-center rounded-lg px-3 text-left text-ink hover:bg-surface"` +
        ` data-action="school-picker#selectSchool" data-id="${this.escape(String(school.id))}">` +
        `${this.escape(label)}</button></li>`
    }).join("")
    this.resultsTarget.hidden = false
  }

  setOptions(select, options, placeholder) {
    const parts = [`<option value="">${this.escape(placeholder)}</option>`]
    options.forEach((option) => {
      parts.push(`<option value="${this.escape(String(option.value))}">${this.escape(option.label)}</option>`)
    })
    select.innerHTML = parts.join("")
  }

  // 선택 표시(선택한 학교명). 값이 있으면 노출, 없으면 감춘다.
  setSelected(label) {
    if (!this.hasSelectedTarget) return
    const text = (label || "").trim()
    this.selectedTarget.textContent = text
    this.selectedTarget.hidden = text.length === 0
  }

  clearResults() {
    if (!this.hasResultsTarget) return
    this.resultsTarget.innerHTML = ""
    this.resultsTarget.hidden = true
  }

  resetSchool() {
    this.schoolTarget.value = ""
    this.setSelected("")
    this.clearResults()
    this.resetClassroom()
  }

  resetClassroom() {
    if (!this.hasClassroomTarget) return
    this.setOptions(this.classroomTarget, [], "학급 없음")
    this.classroomTarget.disabled = true
  }

  regionLabel(region) {
    return (region || "").replace(/교육청$/, "")
  }

  async fetchJson(url) {
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) return []
      return await response.json()
    } catch (_error) {
      return []
    }
  }

  escape(value) {
    const holder = document.createElement("div")
    holder.textContent = value == null ? "" : String(value)
    return holder.innerHTML
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
