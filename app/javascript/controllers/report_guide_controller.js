import { Controller } from "@hotwired/stimulus"

// 안내형 독후감 작성(guided compose, §1a). 질문 카드마다 답변을 받아 두었다가
// "초안 만들기"를 누르면 답을 이어 붙여 실제 제출 폼(_form)의 본문 textarea 를 채운다.
// 질문 textarea 는 name 이 없어 서버로 전송되지 않는다 — 여기서 조립한 결과만 제출된다.
//
// **저장은 폼의 report-autosave 가 맡는다**(2026-09-12 자동 저장 되살림, docs/improve §5-1).
// 2026-09-04 에 localStorage 자동 저장을 걷어내고 '임시 저장' 버튼 + beforeunload 경고로 바꿨다가,
// 베타 검토에서 저장 안 한 글이 사라지는 사례가 나와 서버 초안 자동 저장으로 되살렸다.
// 이 컨트롤러는 답을 쓰는 동안 본문 필드를 계속 맞춰 두고(sync) input 이벤트를 흘려, 질문
// 단계에서도 지금까지의 답이 초안으로 저장되게 한다. 이탈 경고도 report-autosave 가 한다
// (저장이 끝난 뒤에는 붙잡지 않고, 저장 못 한 내용이 있을 때만 붙잡는다).
export default class extends Controller {
  static targets = ["answer", "questions", "form", "notice", "skipLink", "status"]

  connect() {
    // 그레이스풀: _form 은 기본 표시라 JS 미로딩 시 질문+폼이 함께 보인다(직접 작성·제출 가능).
    // JS 가 붙으면 조립 전까지 폼을 숨겨 질문 단계에 집중하게 한다.
    if (this.hasFormTarget) this.formTarget.classList.add("hidden")
    this.assembled = false

    this.reset = this.reset.bind(this)
    document.addEventListener("turbo:before-cache", this.reset)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.reset)
  }

  // turbo:before-cache — 캐시될 스냅샷을 "질문 보임 + 폼 숨김"(조립 전 기본 상태)으로 되돌려
  // 뒤로가기/캐시 복원 시 조립된 상태가 잠깐 비치지 않게 한다(guide_modal 과 동일 패턴).
  // (자동 저장 화면은 스냅샷을 남기지 않지만 — _form 의 turbo_exempts_page_from_cache — 방어로 둔다.)
  reset() {
    if (this.hasQuestionsTarget) this.questionsTarget.classList.remove("hidden")
    if (this.hasFormTarget) this.formTarget.classList.add("hidden")
    if (this.hasNoticeTarget) this.noticeTarget.classList.add("hidden")
    if (this.hasSkipLinkTarget) this.skipLinkTarget.classList.remove("hidden")
  }

  // 답을 쓰는 동안 숨은 본문 필드를 지금까지의 답으로 맞춘다. 자동 저장이 폼을 통째로 보내므로
  // 이게 곧 질문 단계의 저장이다. 조립(초안 만들기) 뒤에는 아이가 본문을 직접 고치므로 덮어쓰지 않는다.
  sync() {
    if (this.assembled) return

    const bodyField = this.bodyField
    if (!bodyField) return

    bodyField.value = this.composedBody()
    bodyField.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // 첫 자동 저장으로 초안이 생겼다(report-autosave:created). "질문 없이 바로 쓰기"가 새 빈 글이
  // 아니라 **이 초안**으로 가게 한다 — 안 그러면 누르는 순간 '작성 중' 글이 두 편 생기고, 지금까지
  // 쓴 답은 다른 글에 남는다.
  draftCreated(event) {
    const editUrl = event.detail?.editUrl
    if (editUrl && this.hasSkipLinkTarget) this.skipLinkTarget.setAttribute("href", editUrl)
  }

  // 자동 저장 상태(report-autosave:status)를 질문 영역에도 보여 준다 — 답을 쓰는 동안은 폼(과 그
  // 안의 상태 문구)이 숨겨져 있다. 이 단계의 다음 행동은 '제출하기'가 아니라 '초안 만들기'다.
  showStatus(event) {
    if (!this.hasStatusTarget) return

    const { text, tone, time } = event.detail || {}
    this.statusTarget.textContent = time ? `${time}에 저장했어요. 다 답하면 ‘초안 만들기’를 눌러요.` : text
    this.statusTarget.classList.toggle("form-hint", tone !== "error")
    this.statusTarget.classList.toggle("form-error", tone === "error")
  }

  // 답변들을 문단 구분(빈 줄)으로 이어 붙여 본문 필드를 채우고, 질문 패널을 감추고
  // 제출 폼을 드러낸다. name 없는 질문 textarea 의 값은 여기서만 서버 제출 필드로 옮겨진다.
  // 반환: 조립에 성공했는지(임시 저장이 이 값으로 진행 여부를 판단한다).
  assemble() {
    const bodyField = this.bodyField
    if (!bodyField) return false

    const body = this.composedBody()

    // 답변이 하나도 없으면 빈 본문 폼으로 넘어가지 않고 질문 단계에 머문다(오조작 방지).
    // 아이가 눈치채도록 안내 문구를 함께 보여 준다.
    if (body.length === 0) {
      if (this.hasNoticeTarget) this.noticeTarget.classList.remove("hidden")
      const firstAnswer = this.answerTargets[0]
      if (firstAnswer) firstAnswer.focus()
      return false
    }
    if (this.hasNoticeTarget) this.noticeTarget.classList.add("hidden")

    bodyField.value = body
    bodyField.dispatchEvent(new Event("input", { bubbles: true }))
    bodyField.dispatchEvent(new Event("change", { bubbles: true }))
    this.assembled = true

    if (this.hasQuestionsTarget) this.questionsTarget.classList.add("hidden")
    if (this.hasFormTarget) this.formTarget.classList.remove("hidden")
    // "질문 없이 바로 쓰기"는 상단 카드(questions 컨테이너 밖)에 있어 질문을 접어도 살아남는다.
    // 조립 후 남겨 두면 아이가 눌렀을 때 GET 이동이라 방금 만든 본문이 통째로 사라진다.
    if (this.hasSkipLinkTarget) this.skipLinkTarget.classList.add("hidden")

    bodyField.scrollIntoView({ behavior: "smooth", block: "center" })
    bodyField.focus()
    return true
  }

  // 질문 화면의 "임시 저장" — 답변을 본문으로 조립한 뒤 제출 폼의 save_draft 버튼을 눌러
  // 서버 초안으로 저장한다. 조립이 실패하면(답변 0개) 아무것도 보내지 않는다.
  saveDraft() {
    if (!this.assemble()) return
    if (!this.hasFormTarget) return

    const form = this.formTarget.querySelector("form")
    const draftButton = form && form.querySelector("input[name='save_draft']")
    if (!form || !draftButton) return

    form.requestSubmit(draftButton)
  }

  get bodyField() {
    return this.element.querySelector("#report_body_field")
  }

  composedBody() {
    return this.answerTargets
      .map((target) => target.value.trim())
      .filter((value) => value.length > 0)
      .join("\n\n")
  }
}
