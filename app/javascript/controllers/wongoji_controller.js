import { Controller } from "@hotwired/stimulus"

// 원고지(20x10=200칸) 입력을 숨은 body 텍스트에어리어와 동기화한다.
// 의존성 없이 순수 DOM 으로 구현. (P3.2)
export default class extends Controller {
  static targets = ["input", "grid", "modeRadio"]
  static values = { columns: { type: Number, default: 20 }, rows: { type: Number, default: 10 } }

  connect() {
    this.buildGrid()
    this.syncFromInput()
    this.switchMode()
  }

  // 선택된 입력 방식에 따라 원고지 격자 표시/숨김.
  switchMode() {
    if (!this.hasGridTarget) return
    const selected = this.modeRadioTargets.find((radio) => radio.checked)
    const mode = selected ? selected.value : "keyboard"
    this.gridTarget.classList.toggle("hidden", mode !== "wongoji")
  }

  buildGrid() {
    if (!this.hasGridTarget) return

    const total = this.columnsValue * this.rowsValue
    const table = document.createElement("div")
    table.style.display = "grid"
    table.style.gridTemplateColumns = `repeat(${this.columnsValue}, 1.5rem)`
    table.style.gap = "2px"

    this.cells = []
    for (let i = 0; i < total; i++) {
      const cell = document.createElement("input")
      cell.type = "text"
      cell.maxLength = 1
      cell.className = "h-6 w-6 border border-amber-300 bg-white text-center text-sm"
      cell.addEventListener("input", () => this.syncToInput())
      this.cells.push(cell)
      table.appendChild(cell)
    }

    this.gridTarget.replaceChildren(table)
  }

  // 격자 → 텍스트에어리어.
  syncToInput() {
    if (!this.hasInputTarget || !this.cells) return
    this.inputTarget.value = this.cells.map((cell) => cell.value).join("")
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // 텍스트에어리어 → 격자.
  syncFromInput() {
    if (!this.hasInputTarget || !this.cells) return
    const chars = Array.from(this.inputTarget.value)
    this.cells.forEach((cell, index) => {
      cell.value = chars[index] || ""
    })
  }
}
