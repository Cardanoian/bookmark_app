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
// · 입력이 멈추고 2초 뒤 저장하고, 쉬지 않고 쓰는 중이면 20초마다 한 번은 저장한다. 새 글의 첫
//   저장은 첫 입력 0.8초 뒤에 바로 한다(초안이 생기기 전에 새로고침하면 빈 새 글로 돌아가므로).
//   화면을 떠날 때(Turbo 이동·새로고침·창 닫기·앱이 화면을 닫음·탭 전환)는 그 자리에서 한 번 더(keepalive).
//   keepalive 한도(64KiB)를 넘는 아주 긴 글은 보통 요청으로 보내고, 창을 닫을 때는 붙잡는다.
// · 저장은 한 번에 하나(single-flight). 새 글의 첫 저장이 초안을 만들면 폼을 그 초안의 PATCH 로
//   바꾼다 — 안 바꾸면 '제출하기'가 create 로 한 편을 더 만든다. 첫 저장이 날아가는 중에 제출을
//   누르면 끝날 때까지 기다렸다가 PATCH 로 낸다(기다리는 동안 버튼을 잠근다).
// · 저장할 때마다 "내가 본 초안"의 버전(draft_version)을 싣는다. 그사이 다른 탭·기기가 초안을 더
//   고쳤으면 서버가 409 stale 로 거절하고, 여기서는 멈추고 새로 고치게 한다(옛 화면이 새 글을 덮지 않게).
// · enabled=false(사진 첫 제출 화면·이미 낸 글 수정·담임이 연 학생 초안)면 저장하지 않고, 쓴 게
//   있으면 떠날 때 경고만 한다.
// · 응답은 셋으로 가른다. 5xx·네트워크 오류·시간 초과는 간격을 벌려 다시 시도한다. 검증 실패(422 +
//   errors)는 아이가 고칠 때까지 기다린다. 그 밖(409·로그인 풀림·권한·보안 토큰 불일치 422 등)은 다시
//   보내도 같으므로 멈추고 새로 고치게 한다. 어느 쪽이든 저장 못 한 글은 '저장 안 됨'으로 남아 떠날 때 붙잡는다.
// · '저장'이 '제출'로 읽히지 않게 저장 문구마다 남은 행동(제출하기)을 함께 적는다.
const DEBOUNCE_MS = 2000
const FIRST_SAVE_DELAY_MS = 800
const MAX_WAIT_MS = 20000
const REQUEST_TIMEOUT_MS = 15000
// 브라우저는 keepalive 요청 본문을 한 문서에서 합쳐 64KiB 까지만 보낸다(넘으면 보내지도 않고 곧바로
// 실패한다). 한글은 한 글자에 3바이트라 약 2만 자를 넘는 글이 걸린다. 어림값에 여유를 두고 자른다.
const KEEPALIVE_MAX_BYTES = 60 * 1024
const RETRY_DELAYS_MS = [ 5000, 15000, 30000, 60000 ]
const LEAVE_WARNING = "아직 저장하지 못한 내용이 있어요. 이 화면을 나갈까요?"
const RELOAD_HINT = "쓴 글을 복사해 둔 뒤 화면을 새로 고쳐 주세요."
const BOOK_FIELDS = [ "report[book_id]", "report[remote_isbn]", "report[book_title]" ]

export default class extends Controller {
  static targets = [ "status", "version" ]
  static values = { enabled: Boolean, submitLabel: { type: String, default: "제출하기" } }

  connect() {
    // 입력마다 version 을 올리고, 저장이 끝나면 그 저장이 담은 version 을 savedVersion 에 적는다.
    // 저장이 날아가는 동안 더 쓴 글은 version > savedVersion 으로 남아 다음 저장이 가져간다.
    this.version = 0
    this.savedVersion = 0
    this.inflight = null
    this.inflightCreating = false
    this.queued = false
    this.failures = 0
    this.stopped = false
    this.rejected = false
    // submitting: 제출(또는 임시 저장 버튼)을 눌렀다 — 자동 저장을 멈춘다.
    // submissionSent: Turbo 가 실제로 제출을 보냈다 — 이제 떠나도 붙잡지 않는다.
    this.submitting = false
    this.submissionSent = false
    this.awaitingSubmit = false
    this.disconnected = false
    this.debounceTimer = null
    this.firstPendingAt = null
    // 새 글 화면 주소. 첫 저장이 서버에 알려, 이 주소로 다시 오면(새로고침·뒤로 가기·앱이 다시 엶)
    // 빈 새 글 대신 초안을 연다. 떠나는 순간의 저장에서는 location 이 이미 다음 화면이라 지금 잡아 둔다.
    this.origin = window.location.pathname + window.location.search

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
    this.disconnected = true
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
    if (!this.enabledValue || this.stopped || this.disconnected) return

    if (this.creating) {
      // 새 글의 첫 저장은 뒤따르는 입력으로 미루지 않는다. 날아가는 중이면 끝난 뒤 afterSave 가 잇는다.
      if (!this.debounceTimer && !this.inflight) this.scheduleSave(FIRST_SAVE_DELAY_MS)
      return
    }

    this.firstPendingAt ??= Date.now()
    const waited = Date.now() - this.firstPendingAt
    this.scheduleSave(waited >= MAX_WAIT_MS ? 0 : DEBOUNCE_MS)
  }

  // 제출(또는 임시 저장 버튼) 직전. 새 글의 첫 저장이 초안을 만드는 중이면 그대로 내보낼 때 create 로
  // 한 편이 더 생긴다 — 끝날 때까지 기다렸다가(그사이 폼은 PATCH 로 바뀐다) 같은 버튼으로 다시 낸다.
  // 이미 있는 초안의 저장(PATCH)이 날아가는 중이면 기다리지 않는다 — 같은 글에 대한 요청이라 순서가
  // 바뀌어도 한 편이고, 제출이 먼저 닿으면 서버가 뒤늦은 자동 저장을 거절한다(이미 제출됨).
  beforeSubmit(event) {
    // 기다리는 동안 또 누르면 쌓지 않는다(연타마다 제출이 하나씩 쌓였다).
    if (this.awaitingSubmit) {
      event.preventDefault()
      return
    }

    this.clearTimers()
    this.submitting = true
    if (!this.inflight || !this.inflightCreating) return

    event.preventDefault()
    this.awaitingSubmit = true
    const submitter = event.submitter ?? null
    if (submitter) submitter.disabled = true
    this.showStatus("저장하는 중이에요. 끝나면 바로 낼게요.")

    // 저장은 REQUEST_TIMEOUT_MS 안에 끝난다(시간 초과도 끝난 것으로 본다). 실패했으면 폼은 그대로
    // create 라 제출이 새 글을 만든다 — 초안이 없었으니 한 편이다.
    this.inflight.finally(() => {
      this.awaitingSubmit = false
      if (submitter) submitter.disabled = false
      if (this.element.isConnected) this.element.requestSubmit(submitter)
    })
  }

  // Turbo 가 제출을 실제로 보냈다. 이제부터는 제출이 곧 저장이므로 떠나는 경고를 끈다.
  // (제출 버튼을 누른 순간이 아니라 여기서 끈다 — 첫 저장을 기다리는 동안 창을 닫으면 잃는다.)
  submissionStarted() {
    this.submissionSent = true
    window.removeEventListener("beforeunload", this.handleBeforeUnload)
  }

  // 제출이 화면을 바꾸지 못하고 끝났을 때(네트워크 오류 등)만 온다. 서버가 응답한 실패(422)는
  // 새 화면이 그려져 이 컨트롤러가 새로 붙는다. 여기서 되살리지 않으면 자동 저장이 멈춘 채 남는다.
  submitEnded(event) {
    if (event.detail?.success) return

    this.submitting = false
    this.submissionSent = false
    window.addEventListener("beforeunload", this.handleBeforeUnload)
    if (this.dirty && !this.disconnected) this.scheduleSave(DEBOUNCE_MS)
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
    const sentBook = this.bookSnapshot
    const payload = this.buildPayload(creating)
    // 한도를 넘는 글은 keepalive 없이 보낸다(Turbo 이동·탭 전환에서는 문서가 남아 있어 끝까지 간다).
    // 창을 닫는 순간에는 끊길 수 있으므로 handleBeforeUnload 가 먼저 붙잡는다.
    const useKeepalive = keepalive && this.payloadBytes(payload) <= KEEPALIVE_MAX_BYTES
    this.showStatus("저장 중…")

    this.inflightCreating = creating
    this.inflight = this.request(payload, useKeepalive)
      .then((response) => this.handleResponse(response, { version, creating, sentBook }))
      .catch(() => this.handleFailure())
      .finally(() => this.afterSave())
  }

  // 떠나는 순간의 저장. 진행 중인 저장이 있으면 겹쳐 보내지 않는다(새 글이면 초안이 두 편 생긴다).
  // 그사이 더 쓴 글은 진행 중인 저장이 끝난 뒤 afterSave 가 한 번 더 보낸다.
  flush() {
    if (!this.enabledValue || this.stopped || this.submitting || this.inflight || !this.dirty) return
    this.save({ keepalive: true })
  }

  // 새로고침·창 닫기. 자동 저장이 제대로 돌고 있으면 한 번 더 저장하고 붙잡지 않는다. 저장이
  // 날아가는 중이거나(문서가 내려가면 그 요청은 끊길 수 있다) 실패·멈춤·검증 실패·오프라인·경고 전용
  // 폼이거나, 첫 저장을 기다리는 제출이 아직 안 나갔으면 붙잡는다.
  // **아주 긴 글**은 keepalive 한도를 넘어 떠나는 순간의 저장이 곧바로 실패하므로(예전에는 경고 없이
  // 잃었다), 보통 요청으로 먼저 보내 두고 붙잡는다 — 아이가 '머물기'를 고르면 그 저장이 끝난다.
  handleBeforeUnload(event) {
    if (this.submissionSent || !this.dirty) return

    if (!this.submitting && this.canSaveSilently) {
      if (this.fitsKeepalive) {
        this.save({ keepalive: true })
        return
      }
      this.save()
    }
    event.preventDefault()
    event.returnValue = ""
  }

  // Turbo 로 다른 화면에 갈 때. 문서가 그대로라 진행 중인 요청도 끝까지 가므로 막지 않고 저장만 한다.
  handleBeforeVisit(event) {
    if (this.submissionSent || !this.dirty) return

    if (!this.submitting && (this.canSaveSilently || this.inflight)) {
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
    return this.enabledValue && !this.stopped && !this.rejected && !this.inflight && this.failures === 0 && navigator.onLine
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

  // 책 칸(고른 책 id·원격 검색 isbn·제목)의 지금 값. 저장 응답의 책 id 를 심어도 되는지 가를 때 쓴다.
  get bookSnapshot() {
    return BOOK_FIELDS.map((name) => this.field(name)?.value ?? "").join(" ")
  }

  field(name) {
    return this.element.querySelector(`input[name='${name}']`)
  }

  buildPayload(creating) {
    const payload = new FormData(this.element)
    payload.set("save_draft", "1")
    if (creating) payload.set("autosave_origin", this.origin)
    return payload
  }

  get fitsKeepalive() {
    return this.payloadBytes(this.buildPayload(this.creating)) <= KEEPALIVE_MAX_BYTES
  }

  // multipart 본문 크기 어림값 — 칸마다 경계·머리글 몫 128바이트 + 이름·값의 UTF-8 바이트 수.
  payloadBytes(payload) {
    const encoder = new TextEncoder()
    let bytes = 0
    for (const [ name, value ] of payload.entries()) {
      bytes += 128 + encoder.encode(name).length
      bytes += typeof value === "string" ? encoder.encode(value).length : value.size
    }
    return bytes
  }

  request(payload, keepalive) {
    return fetch(this.element.action, {
      method: "POST",
      body: payload,
      keepalive,
      credentials: "same-origin",
      signal: this.timeoutSignal(),
      headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken }
    })
  }

  // 응답 없이 멈춘 저장 하나가 다음 저장과 제출을 한없이 붙잡지 않게 끊는다(끊기면 실패로 보고 다시 시도).
  timeoutSignal() {
    return typeof AbortSignal.timeout === "function" ? AbortSignal.timeout(REQUEST_TIMEOUT_MS) : undefined
  }

  async handleResponse(response, sent) {
    // 로그인이 풀리면 서버는 로그인 화면으로 보내고 fetch 는 그 리다이렉트를 따라간다. 다시 보내도 같다.
    if (response.redirected || response.status === 401) {
      this.stop(`로그인이 풀려서 저장하지 못했어요. ${RELOAD_HINT}`)
      return
    }

    const data = await this.readJson(response)
    if (response.ok && data) {
      this.draftSaved(data, sent)
      return
    }
    if (response.status === 409) {
      this.stop(data?.error === "stale"
        ? "다른 곳에서 이 글을 더 고쳤어요. 화면을 새로 고치면 최신 글을 볼 수 있어요."
        : "이미 제출한 글이에요. 화면을 새로 고쳐 주세요.")
      return
    }
    if (response.status === 422 && Array.isArray(data?.errors)) {
      // 검증 실패(책 제목을 지웠다 등). 다시 보내도 같은 결과라 자동으로 다시 보내지 않고, 아이가
      // 고치면 다음 입력이 다시 저장을 부른다. 저장된 것은 아니므로 떠날 때는 붙잡는다.
      this.rejected = true
      this.showStatus("저장하지 못했어요. 책 제목과 내용을 확인해 주세요.", "error")
      return
    }
    // 서버·중계 장애만 다시 시도한다.
    if (response.status >= 500) throw new Error(`autosave failed: ${response.status}`)

    // 422(검증 오류 목록 없음 — 다른 탭에서 로그아웃·다른 계정 로그인으로 보안 토큰이 바뀜)·403·404
    // 등은 다시 보내도 같다. 예전에는 422 를 '저장 끝'으로 처리해 떠날 때 경고도 없이 글을 잃었다.
    this.stop(`저장하지 못했어요. ${RELOAD_HINT}`)
  }

  async readJson(response) {
    if (!(response.headers.get("content-type") || "").includes("json")) return null
    try {
      return await response.json()
    } catch {
      return null
    }
  }

  draftSaved(draft, { version, creating, sentBook }) {
    if (creating) this.adoptDraft(draft)
    if (draft.draft_version && this.hasVersionTarget) this.versionTarget.value = draft.draft_version
    this.syncBook(draft.book_id, sentBook)
    this.savedVersion = Math.max(this.savedVersion, version)
    this.failures = 0
    this.rejected = false
    this.showSaved()
  }

  handleFailure() {
    this.failures += 1
    clearTimeout(this.retryTimer)
    // 떠난 화면에서는 다시 시도하지 않는다(떠나는 순간의 저장은 이미 보냈다).
    if (this.disconnected) return
    if (!navigator.onLine) {
      // online 이벤트가 다시 부른다.
      this.showStatus("인터넷 연결이 끊겼어요. 연결되면 다시 저장할게요.", "error")
      return
    }
    // 실패가 이어질수록 간격을 벌린다. 성공하면 draftSaved 가 failures 를 0 으로 되돌린다.
    const delay = RETRY_DELAYS_MS[Math.min(this.failures - 1, RETRY_DELAYS_MS.length - 1)]
    this.showStatus("저장하지 못했어요. 잠시 뒤 다시 저장할게요.", "error")
    this.retryTimer = setTimeout(() => this.save(), delay)
  }

  afterSave() {
    this.inflight = null
    this.inflightCreating = false
    const again = this.queued || this.dirty
    this.queued = false
    if (!again || this.submitting || this.stopped || this.rejected || this.failures > 0) return

    // 화면을 떠난 뒤에는 타이머를 걸지 않는다 — 몇 초 뒤 떠난 화면의 옛 글을 보내게 된다. 떠나는
    // 사이 더 쓴 글만 한 번 보낸다. 첫 저장이 방금 초안을 만들었다면 폼이 이미 PATCH 로 바뀌어 있다.
    if (this.disconnected) {
      if (!this.creating) this.save({ keepalive: true })
      return
    }
    this.scheduleSave(DEBOUNCE_MS)
  }

  // 첫 저장으로 초안이 생겼다. 폼을 그 초안의 PATCH 로 바꾸고, 새로고침해도 이어 쓰도록 주소를
  // 편집 화면으로 바꾼다. 폼은 화면을 떠난 뒤에 응답이 와도 바꾼다 — 안 바꾸면 떠나는 사이 더 쓴
  // 글의 마지막 저장이 create 로 초안을 한 편 더 만든다. 주소는 이 화면에 있을 때만 바꾼다.
  adoptDraft({ update_url: updateUrl, edit_url: editUrl }) {
    this.element.setAttribute("action", updateUrl)
    if (this.creating) {
      const method = document.createElement("input")
      method.type = "hidden"
      method.name = "_method"
      method.value = "patch"
      method.autocomplete = "off"
      this.element.prepend(method)
    }

    if (editUrl && !this.disconnected && this.element.isConnected) this.replaceLocation(editUrl)
  }

  // 서버가 저장한 책 id 를 숨은 칸에 심는다 — 원격 검색으로 고른 책은 저장하며 서버가 등록하는데,
  // 숨은 book_id 가 빈 채면 다음 저장이 연결을 끊고 isbn 이 남으면 또 등록하려 든다. 단, 요청을 보낸
  // 뒤 아이가 책을 바꿨으면 건드리지 않는다(옛 책 id 를 도로 심으면 다음 저장이 바꾼 책을 되돌린다).
  syncBook(bookId, sentBook) {
    if (!bookId || sentBook !== this.bookSnapshot) return

    const bookField = this.field("report[book_id]")
    if (bookField) bookField.value = bookId
    const isbnField = this.field("report[remote_isbn]")
    if (isbnField) isbnField.value = ""
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

  scheduleSave(delay) {
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = null
      this.save()
    }, delay)
  }

  stop(message) {
    this.stopped = true
    this.clearTimers()
    this.showStatus(message, "error")
  }

  clearTimers() {
    clearTimeout(this.debounceTimer)
    clearTimeout(this.retryTimer)
    this.debounceTimer = null
  }

  showSaved() {
    const time = new Intl.DateTimeFormat("ko-KR", { hour: "numeric", minute: "2-digit" }).format(new Date())
    this.showStatus(`${time}에 저장했어요. 다 쓰면 ‘${this.submitLabelValue}’를 눌러요.`, "hint", { time })
  }

  // 상태 문구를 바꾸고 report-autosave:status 로도 알린다. 질문형 작성은 답을 쓰는 동안 이 폼이
  // 숨겨져 있어, report-guide 가 이 알림을 받아 질문 영역에 같은 상태를 보여 준다.
  showStatus(text, tone = "hint", { time } = {}) {
    if (this.disconnected) return

    this.dispatch("status", { detail: { text, tone, time } })
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = text
    this.statusTarget.classList.toggle("form-hint", tone !== "error")
    this.statusTarget.classList.toggle("form-error", tone === "error")
  }
}
