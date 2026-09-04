import { Controller } from "@hotwired/stimulus"

// 안내형 독후감 작성(guided compose, §1a). 질문 카드마다 답변을 받아 두었다가
// "초안 만들기"를 누르면 답을 이어 붙여 실제 제출 폼(_form)의 본문 textarea 를 채운다.
// 질문 textarea 는 name 이 없어 서버로 전송되지 않는다 — 여기서 조립한 결과만 제출된다.
//
// **자동 저장은 하지 않는다.** 예전에는 답변을 입력할 때마다 localStorage 에 써 두고 "이어서
// 쓰기" 배너로 복원했는데, 사용자가 "자동으로 임시저장되지 않게 하고 임시 저장 버튼을 달라"고
// 요구해 그 경로를 걷어냈다. 대신 "임시 저장"이 답변을 조립해 **서버 초안**으로 저장한다
// (상태가 브라우저와 DB 두 곳으로 갈리지 않게 한 곳으로 모은 결정).
// 그 대가로 "저장을 안 누르고 이탈하면 소실"이라는 실패 모드가 새로 생기므로 beforeunload 로 경고한다.
export default class extends Controller {
  static targets = ["answer", "questions", "form", "notice", "skipLink"]

  connect() {
    // 그레이스풀: _form 은 기본 표시라 JS 미로딩 시 질문+폼이 함께 보인다(직접 작성·제출 가능).
    // JS 가 붙으면 조립 전까지 폼을 숨겨 질문 단계에 집중하게 한다.
    if (this.hasFormTarget) this.formTarget.classList.add("hidden")

    this.reset = this.reset.bind(this)
    document.addEventListener("turbo:before-cache", this.reset)

    this.warnBeforeUnload = this.warnBeforeUnload.bind(this)
    window.addEventListener("beforeunload", this.warnBeforeUnload)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.reset)
    window.removeEventListener("beforeunload", this.warnBeforeUnload)
  }

  // turbo:before-cache — 캐시될 스냅샷을 "질문 보임 + 폼 숨김"(조립 전 기본 상태)으로 되돌려
  // 뒤로가기/캐시 복원 시 조립된 상태가 잠깐 비치지 않게 한다(guide_modal 과 동일 패턴).
  reset() {
    if (this.hasQuestionsTarget) this.questionsTarget.classList.remove("hidden")
    if (this.hasFormTarget) this.formTarget.classList.add("hidden")
    if (this.hasNoticeTarget) this.noticeTarget.classList.add("hidden")
    if (this.hasSkipLinkTarget) this.skipLinkTarget.classList.remove("hidden")
  }

  // 자동 저장이 없으므로, 쓴 답변이 있는 채 창을 닫으면 그대로 사라진다. 초등 전학년이 쓰는
  // 화면이라 최소한 경고는 띄운다(문구는 브라우저가 정한다 — 커스텀 텍스트는 무시된다).
  warnBeforeUnload(event) {
    if (!this.hasAnswers()) return

    event.preventDefault()
    event.returnValue = ""
  }

  hasAnswers() {
    return this.answerTargets.some((target) => target.value.trim().length > 0)
  }

  // 답변들을 문단 구분(빈 줄)으로 이어 붙여 본문 필드를 채우고, 질문 패널을 감추고
  // 제출 폼을 드러낸다. name 없는 질문 textarea 의 값은 여기서만 서버 제출 필드로 옮겨진다.
  // 반환: 조립에 성공했는지(임시 저장이 이 값으로 진행 여부를 판단한다).
  assemble() {
    const bodyField = this.element.querySelector("#report_body_field")
    if (!bodyField) return false

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
      return false
    }
    if (this.hasNoticeTarget) this.noticeTarget.classList.add("hidden")

    bodyField.value = body
    bodyField.dispatchEvent(new Event("input", { bubbles: true }))
    bodyField.dispatchEvent(new Event("change", { bubbles: true }))

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

    // 이탈 경고를 끈 뒤 제출한다 — 저장하러 가는 길에 경고가 뜨면 안 된다.
    window.removeEventListener("beforeunload", this.warnBeforeUnload)
    form.requestSubmit(draftButton)
  }
}
