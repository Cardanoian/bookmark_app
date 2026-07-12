import { Controller } from "@hotwired/stimulus"

// 학교 선택 하이브리드 피커(계획 §2.4). 시도(region)→시군구(gu) 캐스케이딩으로 학교 목록을
// 좁히고, 이름검색으로도 같은 학교 셀렉트를 채운다. gu 가 비거나 부정확한 학교도 이름검색으로
// 항상 도달 가능(graceful degrade — gu 는 핵심 경로의 하드 의존이 아니다). 학교 셀렉트가 곧
// school_id(name="school_id")다. 로그인 폼(classroom 타깃 존재)이면 선택 학교의 학급만
// 스코프 조회해 종속 드롭다운을 채운다(전국 전량 로드 제거).
export default class extends Controller {
  static targets = ["region", "gu", "query", "school", "classroom"]

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
    if (query.length < 2) return

    this.fetchJson(`/schools/search?q=${encodeURIComponent(query)}`).then((schools) => this.fillSchools(schools))
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

  fillSchools(schools) {
    const options = (schools || []).map((school) => ({
      value: school.id,
      label: school.gu
        ? `${school.name} (${this.regionLabel(school.region)} ${school.gu})`
        : `${school.name} (${this.regionLabel(school.region)})`
    }))
    const placeholder = options.length ? "학교를 선택하세요" : "일치하는 학교가 없어요"
    this.setOptions(this.schoolTarget, options, placeholder)
    this.resetClassroom()
  }

  setOptions(select, options, placeholder) {
    const parts = [`<option value="">${this.escape(placeholder)}</option>`]
    options.forEach((option) => {
      parts.push(`<option value="${this.escape(String(option.value))}">${this.escape(option.label)}</option>`)
    })
    select.innerHTML = parts.join("")
  }

  resetSchool() {
    this.setOptions(this.schoolTarget, [], "시도·시군구를 고르거나 이름으로 검색하세요")
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
