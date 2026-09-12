import { Controller } from "@hotwired/stimulus"

// 독후감 자동 저장(2026-09-12 되살림 — docs/improve/베타피드백_통합정리.md §5-1, WR-1).
//
// 왜 되살렸나: 2026-09-04 에 질문형 작성의 localStorage 자동 저장을 걷어내고 '임시 저장' 버튼으로
// 바꿨는데, 베타 검토(09-11)에서 고쳐쓰기 화면에 쓴 4,822자가 새로고침 한 번에 사라졌다. 그때
// 위험을 줄이려고 둔 이탈 경고는 질문형 작성 화면에만 있었다.
//
// 설계
// · 저장 위치는 **서버 초안**이다(임시 저장과 같은 save_draft 경로를 JSON 으로 부른다). 상태가
//   브라우저와 DB 두 곳으로 갈리지 않고, 다른 기기에서도 이어 쓸 수 있고, 공용 기기에 앞 학생의
//   글이 남지 않는다.
// · 입력이 멈추고 2초 뒤 저장하고, 쉬지 않고 쓰는 중이면 20초마다 한 번은 저장한다. 화면을 떠날
//   때(Turbo 이동·새로고침·창 닫기·앱이 화면을 닫음·탭 전환)는 그 자리에서 한 번 더(keepalive).
// · 저장은 한 번에 하나(single-flight). 새 글의 첫 저장이 초안을 만들면 폼을 그 초안의 PATCH 로
//   바꾼다 — 안 바꾸면 '제출하기'가 create 로 한 편을 더 만든다. 첫 저장이 날아가는 중에 제출을
//   누르면 끝날 때까지 기다렸다가 PATCH 로 낸다.
// · enabled=false(사진 첫 제출 화면·이미 낸 글 수정)면 저장하지 않고, 쓴 게 있으면 떠날 때 경고만 한다.
// · 서버가 409(이미 제출됨 — 다른 탭에서 냈다)를 주면 멈춘다. 제출된 글은 자동 저장이 못 바꾼다.
// · '저장'이 '제출'로 읽히지 않게 저장 문구마다 남은 행동(제출하기)을 함께 적는다.
const DEBOUNCE_MS = 2000
const MAX_WAIT_MS = 20000
const RETRY_DELAYS_MS = [ 5000, 15000, 30000, 60000 ]
const LEAVE_WARNING = "아직 저장하지 못한 내용이 있어요. 이 화면을 나갈까요?"

export default class extends Controller {
  static targets = [ "status" ]
  static values = { enabled: Boolean, submitLabel: { type: String, default: "제출하기" } }

  connect() {
    // 입력마다 version 을 올리고, 저장이 끝나면 그 저장이 담은 version 을 savedVersion 에 적는다.
    // 저장이 날아가는 동안 더 쓴 글은 version > savedVersion 으로 남아 다음 저장이 가져간다.
    this.version = 0
    this.savedVersion = 0
    this.inflight = null
    this.queued = false
    this.failures = 0
    this.stopped = false
    this.submitting = false
    this.firstPendingAt = null

    this.handleBeforeUnload = this.handleBeforeUnload.bind(this)
    this.handleBeforeVisit = this.handleBeforeVisit.bind(this)
    this.handleVisibility = this.handleVisibility.bind(this)
    this.handleOnline = this.handleOnline.bind(this)
    this.flush = this.flush.bind(this)

    window.addEventListener("beforeunload", this.handleBeforeUnload)
    window.addEventListener("pagehide", this.flush)
    window.addEventListener("online", this.handleOnline)
    document.addEventListener("visibilitychange", this.handleVisibility)
    document.addEventListener("turbo:before-visit", this.handleBeforeVisit)
    // 복원 방문(뒤로 가기·앱이 화면을 닫고 이전 화면으로)은 before-visit 을 거치지 않는다.
    document.addEventListener("turbo:visit", this.flush)
  }

  disconnect() {
    this.flush()
    this.clearTimers()
    window.removeEventListener("beforeunload", this.handleBeforeUnload)
    window.removeEventListener("pagehide", this.flush)
    window.removeEventListener("online", this.handleOnline)
    document.removeEventListener("visibilitychange", this.handleVisibility)
    document.removeEventListener("turbo:before-visit", this.handleBeforeVisit)
    document.removeEventListener("turbo:visit", this.flush)
  }

  // 폼 안의 입력(본문·책 제목·책 고르기)마다 부른다. 질문형 작성은 report-guide 가 답을 본문
  // 필드로 옮기며 input 이벤트를 흘려 여기로 들어온다.
  changed() {
    if (this.submitting) return

    this.version += 1
    if (!this.enabledValue || this.stopped) return

    this.firstPendingAt ??= Date.now()
    const waited = Date.now() - this.firstPendingAt
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this.save(), waited >= MAX_WAIT_MS ? 0 : DEBOUNCE_MS)
  }

  // 제출(또는 임시 저장 버튼) 직전. 첫 저장이 초안을 만드는 중이면 그대로 내보낼 때 create 로 한
  // 편이 더 생긴다 — 끝날 때까지 기다렸다가(그사이 폼은 PATCH 로 바뀐다) 같은 버튼으로 다시 낸다.
  beforeSubmit(event) {
    this.clearTimers()
    this.submitting = true
    // 제출이 곧 저장이다. 떠나는 경고와 떠나는 순간의 저장을 끈다.
    window.removeEventListener("beforeunload", this.handleBeforeUnload)

    if (!this.inflight) return

    event.preventDefault()
    const submitter = event.submitter ?? null
    this.inflight.finally(() => this.element.requestSubmit(submitter))
  }

  // 제출이 화면을 바꾸지 못하고 끝났을 때(네트워크 오류 등)만 온다. 서버가 응답한 실패(422)는
  // 새 화면이 그려져 이 컨트롤러가 새로 붙는다. 여기서 되살리지 않으면 자동 저장이 멈춘 채 남는다.
  submitEnded(event) {
    if (event.detail?.success) return

    this.submitting = false
    window.addEventListener("beforeunload", this.handleBeforeUnload)
    if (this.dirty) this.scheduleSave()
  }

  save({ keepalive = false } = {}) {
    if (!this.enabledValue || this.stopped || this.submitting) return
    if (this.inflight) {
      this.queued = true
      return
    }
    if (!this.dirty) return
    // 빈 본문은 서버가 받지 않는다(빈 '작성 중' 글이 목록에 쌓이지 않게). 보낼 것이 없는 상태로 본다.
    if (this.bodyBlank) {
      this.savedVersion = this.version
      return
    }

    this.clearTimers()
    this.firstPendingAt = null
    const version = this.version
    const creating = this.creating
    const payload = new FormData(this.element)
    payload.set("save_draft", "1")
    this.showStatus("저장 중…")

    this.inflight = this.request(payload, keepalive)
      .then((response) => this.handleResponse(response, version, creating))
      .catch(() => this.handleFailure())
      .finally(() => {
        this.inflight = null
        const again = this.queued || this.dirty
        this.queued = false
        if (again && !this.submitting && !this.stopped && this.failures === 0) this.scheduleSave()
      })
  }

  // 떠나는 순간의 저장. 진행 중인 저장이 있으면 겹쳐 보내지 않는다(새 글이면 초안이 두 편 생긴다).
  flush() {
    if (!this.enabledValue || this.stopped || this.submitting || this.inflight || !this.dirty) return
    this.save({ keepalive: true })
  }

  // 새로고침·창 닫기. 자동 저장이 제대로 돌고 있으면 한 번 더 저장하고 붙잡지 않는다. 저장이
  // 날아가는 중이거나(문서가 내려가면 그 요청은 끊길 수 있다) 실패·오프라인·경고 전용 폼이면 붙잡는다.
  handleBeforeUnload(event) {
    if (this.submitting || !this.dirty) return

    if (this.canSaveSilently) {
      this.save({ keepalive: true })
      return
    }
    event.preventDefault()
    event.returnValue = ""
  }

  // Turbo 로 다른 화면에 갈 때. 문서가 그대로라 진행 중인 요청도 끝까지 가므로 막지 않고 저장만 한다.
  handleBeforeVisit(event) {
    if (this.submitting || !this.dirty) return

    if (this.canSaveSilently || this.inflight) {
      this.flush()
      return
    }
    if (!window.confirm(LEAVE_WARNING)) event.preventDefault()
  }

  handleVisibility() {
    if (document.visibilityState === "hidden") this.flush()
  }

  handleOnline() {
    if (this.dirty) this.save()
  }

  // --- private ---

  get dirty() {
    return this.version !== this.savedVersion
  }

  get canSaveSilently() {
    return this.enabledValue && !this.stopped && !this.inflight && this.failures === 0 && navigator.onLine
  }

  // 새 글 폼에는 _method 가 없다(create). 첫 저장 뒤 adoptDraft 가 넣는다.
  get creating() {
    return !this.element.querySelector("input[name='_method']")
  }

  get bodyBlank() {
    const field = this.element.querySelector("#report_body_field")
    return !field || field.value.trim() === ""
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  request(payload, keepalive) {
    return fetch(this.element.action, {
      method: "POST",
      body: payload,
      keepalive,
      credentials: "same-origin",
      headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken }
    })
  }

  async handleResponse(response, version, creating) {
    if (response.status === 409) {
      this.stop("이미 제출한 글이에요. 화면을 새로 고쳐 주세요.")
      return
    }
    if (response.status === 422) {
      // 다시 보내도 같은 결과다. 아이가 고친 뒤의 다음 입력이 다시 저장을 부른다.
      this.savedVersion = version
      this.showStatus("저장하지 못했어요. 책 제목과 내용을 확인해 주세요.", "error")
      return
    }
    // 로그인이 풀리면 서버는 JSON 대신 로그인 화면으로 보낸다. 재시도해도 소용없다.
    if (!(response.headers.get("content-type") || "").includes("json")) {
      this.stop("로그인이 풀려서 저장하지 못했어요. 쓴 글을 복사해 둔 뒤 다시 로그인해 주세요.")
      return
    }
    if (!response.ok) throw new Error(`autosave failed: ${response.status}`)

    const draft = await response.json()
    // 화면을 떠난 뒤(keepalive) 도착한 응답이 새 화면의 주소를 바꾸면 안 된다.
    if (creating && this.element.isConnected) this.adoptDraft(draft)
    this.savedVersion = Math.max(this.savedVersion, version)
    this.failures = 0
    this.showSaved()
  }

  handleFailure() {
    this.failures += 1
    clearTimeout(this.retryTimer)
    if (!navigator.onLine) {
      // online 이벤트가 다시 부른다.
      this.showStatus("인터넷 연결이 끊겼어요. 연결되면 다시 저장할게요.", "error")
      return
    }
    // 실패가 이어질수록 간격을 벌린다. 성공하면 handleResponse 가 failures 를 0 으로 되돌린다.
    const delay = RETRY_DELAYS_MS[Math.min(this.failures - 1, RETRY_DELAYS_MS.length - 1)]
    this.showStatus("저장하지 못했어요. 잠시 뒤 다시 저장할게요.", "error")
    this.retryTimer = setTimeout(() => this.save(), delay)
  }

  // 첫 저장으로 초안이 생겼다. 폼을 그 초안의 PATCH 로 바꾸고, 새로고침해도 이어 쓰도록 주소를
  // 편집 화면으로 바꾼다.
  adoptDraft({ update_url: updateUrl, edit_url: editUrl, book_id: bookId }) {
    this.element.setAttribute("action", updateUrl)
    const method = document.createElement("input")
    method.type = "hidden"
    method.name = "_method"
    method.value = "patch"
    method.autocomplete = "off"
    this.element.prepend(method)

    // 원격 검색으로 고른 책은 초안을 만들며 서버가 등록했다. 그 id 를 숨은 칸에 심지 않으면 다음
    // 저장의 빈 book_id 가 연결을 끊고, isbn 을 남기면 없는 책을 또 등록하려 든다.
    if (bookId) {
      const bookField = this.element.querySelector("input[name='report[book_id]']")
      if (bookField) bookField.value = bookId
      const isbnField = this.element.querySelector("input[name='report[remote_isbn]']")
      if (isbnField) isbnField.value = ""
    }

    if (editUrl) this.replaceLocation(editUrl)
    this.dispatch("created", { detail: { editUrl } })
  }

  // Turbo 가 기억하는 현재 주소도 함께 바꾼다(그래야 이 화면에서 다음 이동이 맞게 기록된다).
  // 복원 식별자는 그대로 둔다 — 새로 만들면 뒤로 가기가 이 화면을 못 찾는다.
  replaceLocation(path) {
    const url = new URL(path, window.location.href)
    const turboHistory = window.Turbo?.navigator?.history
    if (turboHistory?.replace) {
      turboHistory.replace(url, turboHistory.restorationIdentifier)
    } else {
      window.history.replaceState(window.history.state, "", url)
    }
  }

  scheduleSave() {
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this.save(), DEBOUNCE_MS)
  }

  stop(message) {
    this.stopped = true
    this.clearTimers()
    this.showStatus(message, "error")
  }

  clearTimers() {
    clearTimeout(this.debounceTimer)
    clearTimeout(this.retryTimer)
  }

  showSaved() {
    const time = new Intl.DateTimeFormat("ko-KR", { hour: "numeric", minute: "2-digit" }).format(new Date())
    this.showStatus(`${time}에 저장했어요. 다 쓰면 ‘${this.submitLabelValue}’를 눌러요.`, "hint", { time })
  }

  // 상태 문구를 바꾸고 report-autosave:status 로도 알린다. 질문형 작성은 답을 쓰는 동안 이 폼이
  // 숨겨져 있어, report-guide 가 이 알림을 받아 질문 영역에 같은 상태를 보여 준다.
  showStatus(text, tone = "hint", { time } = {}) {
    this.dispatch("status", { detail: { text, tone, time } })
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = text
    this.statusTarget.classList.toggle("form-hint", tone !== "error")
    this.statusTarget.classList.toggle("form-error", tone === "error")
  }
}
