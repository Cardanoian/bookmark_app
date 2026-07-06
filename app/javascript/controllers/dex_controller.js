import { Controller } from "@hotwired/stimulus"

// 도감 필터(속성별) + 카드 표시 토글. 의존성 없이 순수 DOM. (P4.7)
export default class extends Controller {
  static targets = ["card", "filter"]

  filter(event) {
    const element = event.currentTarget.dataset.element

    this.cardTargets.forEach((card) => {
      const match = element === "all" || card.dataset.element === element
      card.classList.toggle("hidden", !match)
    })

    this.filterTargets.forEach((button) => {
      button.classList.toggle("ring-2", button.dataset.element === element)
      button.classList.toggle("ring-amber-400", button.dataset.element === element)
    })
  }
}
