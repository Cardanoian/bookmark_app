import { Controller } from "@hotwired/stimulus"

// 안내형 독후감 작성(guided compose, §1a). 질문 카드마다 답변을 받아 두었다가
// "초안 만들기"를 누르면 답을 이어 붙여 실제 제출 폼(_form)의 본문 textarea 를 채운다.
// 질문 textarea 는 name 이 없어 서버로 전송되지 않는다 — 여기서 조립한 결과만 제출된다.
// 답변은 localStorage 에 임시 저장해(사용자·책별로 분리) 새로고침/이탈 후에도 이어 쓸 수 있게 하고,
// 조립 또는 제출이 끝나면 지운다. localStorage 접근은 모두 그레이스풀(실패해도 기능은 그대로 동작).
export default class extends Controller {
  static targets = ["answer", "questions", "form", "banner", "notice"]
  static values = { userId: String }

  connect() {
    // 그레이스풀: _form 은 기본 표시라 JS 미로딩 시 질문+폼이 함께 보인다(직접 작성·제출 가능).
    // JS 가 붙으면 조립 전까지 폼을 숨겨 질문 단계에 집중하게 한다.
    if (this.hasFormTarget) this.formTarget.classList.add("hidden")

    this.reset = this.reset.bind(this)
    document.addEventListener("turbo:before-cache", this.reset)

    this.showDraftBannerIfPresent()
    this.bindFormSubmit()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.reset)
  }

  // turbo:before-cache — 캐시될 스냅샷을 "질문 보임 + 폼 숨김"(조립 전 기본 상태)으로 되돌려
  // 뒤로가기/캐시 복원 시 조립된 상태가 잠깐 비치지 않게 한다(guide_modal 과 동일 패턴).
  reset() {
    if (this.hasQuestionsTarget) this.questionsTarget.classList.remove("hidden")
    if (this.hasFormTarget) this.formTarget.classList.add("hidden")
    if (this.hasNoticeTarget) this.noticeTarget.classList.add("hidden")
  }

  // 각 질문 답변 입력마다 호출(input 이벤트) — 진행 중인 답변을 통째로 저장한다.
  saveDraft() {
    this.writeStorage(this.storageKey(), JSON.stringify(this.answerTargets.map((t) => t.value)))
  }

  restoreDraft() {
    const draft = this.readDraft()
    if (draft) {
      this.answerTargets.forEach((target, index) => {
        if (draft[index] !== undefined) target.value = draft[index]
      })
    }
    this.hideBanner()
  }

  discardDraft() {
    this.clearDraft()
    this.hideBanner()
  }

  // 답변들을 문단 구분(빈 줄)으로 이어 붙여 본문 필드를 채우고, 질문 패널을 감추고
  // 제출 폼을 드러낸다. name 없는 질문 textarea 의 값은 여기서만 서버 제출 필드로 옮겨진다.
  assemble() {
    const bodyField = this.element.querySelector("#report_body_field")
    if (!bodyField) return

    const body = this.answerTargets
      .map((target) => target.value.trim())
      .filter((value) => value.length > 0)
      .join("\n\n")

    // 답변이 하나도 없으면 빈 본문 폼으로 넘어가지 않고 질문 단계에 머문다(오조작 방지).
    // 아이가 눈치채도록 안내 문구를 함께 보여 준다.
    if (body.length === 0) {
      if (this.hasNoticeTarget) this.noticeTarget.classList.remove("hidden")
      const firstAnswer = this.answerTargets[0]
      if (firstAnswer) firstAnswer.focus()
      return
    }
    if (this.hasNoticeTarget) this.noticeTarget.classList.add("hidden")

    bodyField.value = body
    bodyField.dispatchEvent(new Event("input", { bubbles: true }))
    bodyField.dispatchEvent(new Event("change", { bubbles: true }))

    if (this.hasQuestionsTarget) this.questionsTarget.classList.add("hidden")
    if (this.hasFormTarget) this.formTarget.classList.remove("hidden")

    bodyField.scrollIntoView({ behavior: "smooth", block: "center" })
    bodyField.focus()

    this.clearDraft()
  }

  showDraftBannerIfPresent() {
    if (!this.hasBannerTarget) return
    const draft = this.readDraft()
    const hasContent = Array.isArray(draft) && draft.some((value) => typeof value === "string" && value.trim() !== "")
    this.bannerTarget.classList.toggle("hidden", !hasContent)
  }

  hideBanner() {
    if (this.hasBannerTarget) this.bannerTarget.classList.add("hidden")
  }

  // 제출 폼(내부 <form>)이 실제로 제출되면(성공적으로 create 로 넘어가는 경로) 임시 저장을 지운다.
  bindFormSubmit() {
    if (!this.hasFormTarget) return
    const form = this.formTarget.querySelector("form")
    if (!form) return
    form.addEventListener("submit", () => this.clearDraft())
  }

  readDraft() {
    const raw = this.readStorage(this.storageKey())
    if (!raw) return null
    try {
      return JSON.parse(raw)
    } catch (error) {
      return null
    }
  }

  clearDraft() {
    this.removeStorage(this.storageKey())
  }

  // 사용자·책별로 답변을 분리 저장한다. 로그인 사용자가 없으면(값 미설정) "anon"으로 격리한다.
  storageKey() {
    return `guided:${this.userIdValue || "anon"}:${this.bookKey()}`
  }

  bookKey() {
    const bookIdField = this.element.querySelector("#report_book_id")
    if (bookIdField && bookIdField.value) return `id:${bookIdField.value}`

    const bookTitleField = this.element.querySelector("#report_book_title")
    if (bookTitleField && bookTitleField.value) return `title:${bookTitleField.value}`

    return "new"
  }

  readStorage(key) {
    try {
      return window.localStorage.getItem(key)
    } catch (error) {
      return null
    }
  }

  writeStorage(key, value) {
    try {
      window.localStorage.setItem(key, value)
    } catch (error) {
      // localStorage 미지원/차단 시에도 조립·제출은 그대로 동작해야 한다(그레이스풀).
    }
  }

  removeStorage(key) {
    try {
      window.localStorage.removeItem(key)
    } catch (error) {
      // no-op
    }
  }
}
