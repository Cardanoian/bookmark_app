// 학생 보상 순간 효과음(2026-09-19). 소리 파일 없이 Web Audio 오실레이터로 합성한다 —
// 라이선스·NOTICE 표기·자산 용량이 없고 CSP(media-src)도 건드리지 않는다.
// 교실 소음을 고려해 보상 순간(진화·발견·제출·게임 포인트)에만 짧고 작게 울린다.
// 기본은 켜짐이며, 끄기는 기기 단위로 localStorage 에 기억한다(아이 글이 아니라 공용 태블릿에서도 기기 설정이 맞다).
// 어떤 실패(AudioContext 없음·자동 재생 차단·저장소 막힘)도 조용히 넘어간다.

const MUTE_KEY = "chaekgalpi:sfx-muted"
const VOLUME = 0.15

// [주파수(Hz), 시작(초), 길이(초), 파형]
const SOUNDS = {
  evolve: [[523.25, 0, 0.12, "triangle"], [659.25, 0.1, 0.12, "triangle"], [783.99, 0.2, 0.12, "triangle"], [1046.5, 0.3, 0.35, "triangle"]],
  discover: [[1318.51, 0, 0.1, "sine"], [1567.98, 0.08, 0.1, "sine"], [2093.0, 0.16, 0.3, "sine"]],
  reward: [[987.77, 0, 0.08, "square"], [1318.51, 0.08, 0.25, "square"]],
  submit: [[659.25, 0, 0.15, "sine"], [880.0, 0.12, 0.15, "sine"], [1174.66, 0.24, 0.3, "sine"]]
}

let context = null

function audioContext() {
  if (context) return context
  const Ctor = window.AudioContext || window.webkitAudioContext
  if (!Ctor) return null
  try {
    context = new Ctor()
  } catch {
    return null
  }
  return context
}

// 자동 재생 정책은 사용자 제스처 안에서 context 를 만들거나 resume 해야 풀린다. Turbo Drive 는 같은
// 문서를 유지하므로, 한 번 풀어 두면 제출 뒤 리다이렉트된 화면에서도 울린다.
function unlock() {
  if (isMuted()) return
  const ctx = audioContext()
  if (ctx && ctx.state === "suspended") ctx.resume().catch(() => {})
}
document.addEventListener("pointerdown", unlock, { capture: true, passive: true })
document.addEventListener("keydown", unlock, { capture: true, passive: true })

export function isMuted() {
  try {
    return window.localStorage.getItem(MUTE_KEY) === "1"
  } catch {
    return false
  }
}

export function setMuted(muted) {
  try {
    if (muted) window.localStorage.setItem(MUTE_KEY, "1")
    else window.localStorage.removeItem(MUTE_KEY)
  } catch {
    // 저장소가 막힌 환경(사생활 모드 등): 이번 화면에서만 적용되지 않을 뿐 동작은 그대로.
  }
}

// Turbo 캐시 미리보기(뒤로 가기 등)에서 다시 울리지 않게 한다.
export function isPreview() {
  return document.documentElement.hasAttribute("data-turbo-preview")
}

export function play(name) {
  const notes = SOUNDS[name]
  if (!notes || isMuted() || isPreview()) return
  const ctx = audioContext()
  if (!ctx) return
  try {
    if (ctx.state === "suspended") ctx.resume().catch(() => {})
    const start = ctx.currentTime + 0.02
    notes.forEach(([freq, offset, duration, type]) => {
      const osc = ctx.createOscillator()
      const gain = ctx.createGain()
      const t = start + offset
      osc.type = type
      osc.frequency.setValueAtTime(freq, t)
      gain.gain.setValueAtTime(0.0001, t)
      gain.gain.exponentialRampToValueAtTime(VOLUME, t + 0.015)
      gain.gain.exponentialRampToValueAtTime(0.0001, t + duration)
      osc.connect(gain).connect(ctx.destination)
      osc.start(t)
      osc.stop(t + duration + 0.02)
    })
  } catch {
    // 소리는 덤이다 — 실패해도 화면 동작에 영향을 주지 않는다.
  }
}
