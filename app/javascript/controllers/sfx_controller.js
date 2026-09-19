import { Controller } from "@hotwired/stimulus"
import { play } from "sfx"

// 서버가 flash[:sfx] 로 알린 보상 순간(제출·게임 포인트)에 효과음을 한 번 울린다.
// 울린 뒤 요소를 스스로 지워 Turbo 스냅샷에 남지 않게 한다 — 뒤로 가기로 돌아와도 다시 울리지 않는다.
export default class extends Controller {
  static values = { name: String }

  connect() {
    play(this.nameValue)
    this.element.remove()
  }
}
