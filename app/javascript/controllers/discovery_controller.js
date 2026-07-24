import { Controller } from "@hotwired/stimulus"

// 몬스터 발견 축하 모달(영속 드레인). 미연출 UserMonster 큐를 순차로 축하하고,
// 표시되는 즉시 acknowledge 로 celebrated_at 을 마킹해 재노출을 막는다(오프라인/교사
// 트리거 발견도 유실 없이 다음 로드에서 확인). 의존성 없이 순수 DOM + fetch. (WS-F)
export default class extends Controller {
  static targets = ["card", "counter", "advance"]
  static values = { dexNos: Array, acknowledgeUrl: String }

  connect() {
    this.index = 0
    this.render()
    this.acknowledge()
  }

  // 다음 발견으로 진행. 마지막이면 모달을 닫는다.
  next() {
    if (this.index >= this.cardTargets.length - 1) {
      this.close()
      return
    }
    this.index += 1
    this.render()
  }

  close() {
    this.element.remove()
  }

  render() {
    this.cardTargets.forEach((card, i) => {
      card.classList.toggle("hidden", i !== this.index)
    })

    const total = this.cardTargets.length
    if (this.hasCounterTarget) this.counterTarget.textContent = `${this.index + 1} / ${total}`
    if (this.hasAdvanceTarget) this.advanceTarget.textContent = this.index >= total - 1 ? "완료" : "다음"

    // 현재 카드 스프라이트를 잠깐 통통 튀게 하는 등장 연출(monster_care 패턴).
    const sprite = this.cardTargets[this.index]?.querySelector("[data-sprite]")
    if (sprite) {
      sprite.classList.add("animate-bounce")
      setTimeout(() => sprite.classList.remove("animate-bounce"), 1000)
    }
  }

  // celebrated_at 마킹(POST). CSRF 토큰은 meta 에서 읽는다. 실패해도 조용히 무시하며,
  // 그 경우 다음 로드에서 다시 노출된다(영속 드레인의 자연스러운 재시도).
  acknowledge() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const body = new URLSearchParams()
    this.dexNosValue.forEach((dexNo) => body.append("dex_no[]", dexNo))

    fetch(this.acknowledgeUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": token || "",
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "text/plain"
      },
      body: body.toString()
    }).catch(() => {})
  }
}
