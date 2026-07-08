"""
몬스터 숨쉬기 애니메이션 파이프라인 (B안: 1프레임 생성 + 코드 호흡)
====================================================================
Gemini 3.1 Flash Image(나노바나나2, Interactions API)로 몬스터 스프라이트를
"단 한 장"만 생성한 뒤, 숨쉬기(idle breathing)는 코드로 합성한다.

  생성(1콜) → 배경 처리 → 하단 고정 스쿼시/스케일로 N프레임 합성 → WebP

이 방식의 장점:
  - 캐릭터 일관성 100% (같은 픽셀을 코드로 변형하므로 프레임 간 모핑이 없음)
  - 몬스터당 API 호출 1회 (프레임을 AI로 여러 장 뽑지 않음)
  - 호흡 속도/프레임 수/진폭을 코드에서 자유 조정

배경 처리:
  - 실측 결과 현재 Interactions API(gemini-3.1-flash-image)는 jpeg 출력만 지원(png는 400) →
    알파 채널이 없어 투명 배경이 불가능. 따라서 기본은 크로마키(녹색/마젠타).
  - 추후 png/투명 배경을 지원하는 모델이 나오면 BG_MODE="transparent"로 전환.

사용법:
    pip install -r script/requirements.txt   # google-genai pillow numpy
    # 프로젝트 루트 .env 에 GOOGLE_API_KEY=... (또는 GEMINI_API_KEY=...) 저장하면 자동 로드
    python script/monster_sprite_pipeline.py

출력:
    output/<dex>/<step>_<몬스터명>/raw.png            원본 생성 이미지(디버깅용)
    output/<dex>/<step>_<몬스터명>/sprite.png         배경 제거·크롭된 기준 스프라이트
    output/<dex>/<step>_<몬스터명>/frame_NN.png       합성된 숨쉬기 프레임
    output/<dex>/<step>_<몬스터명>/<step>_<몬스터명>.webp 애니메이션 WebP
"""

from __future__ import annotations

import base64
import json
import math
import os
import shutil
import time
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image

# Pillow 버전별 리샘플 상수 호환
try:
    RESAMPLE = Image.Resampling.LANCZOS
except AttributeError:  # Pillow < 9.1
    RESAMPLE = Image.LANCZOS

# ──────────────────────────────────────────────
# 설정
# ──────────────────────────────────────────────
MODEL = "gemini-3.1-flash-image"  # 나노바나나2. 프리뷰면 "gemini-3.1-flash-image-preview"

# 배경 처리 모드
#   "chroma"      : 크로마키(녹색/마젠타). ★ 현재 기본값 (아래 MIME_TYPE 주석 참고)
#   "transparent" : 투명 PNG 직접 출력. 단 현재 API는 jpeg-only라 알파가 없어 사실상 사용 불가.
#                   png/투명 지원 모델이 나오면 이 모드 + MIME_TYPE="image/png"로 전환.
#   "auto"        : transparent 지원 프로브. jpeg-only인 현재는 항상 chroma로 귀결(프로브 생략).
BG_MODE = "chroma"

# 생성 파라미터 (Interactions API response_format)
ASPECT_RATIO = "1:1"   # 단일 몬스터는 정사각이 안전. 키 큰 몬스터는 "3:4"도 가능
IMAGE_SIZE = "2K"      # "512px" | "1K" | "2K" | "4K". 다운샘플용 여유 해상도
MIME_TYPE = "image/jpeg"  # ★ 실측: 이 API/모델은 jpeg만 허용(png는 400). → 알파 불가 → 크로마키 필수

# 프레임/캔버스
OUTPUT_SIZE = 256        # 최종 프레임 한 변(정사각)
BODY_FILL = 0.90         # 캔버스 대비 몬스터 최대 크기 비율(여백 확보)
BOTTOM_MARGIN = 6        # 하단 여백(px). 발이 화면 맨 밑에 딱 붙지 않도록

# 숨쉬기 애니메이션
BREATH_FRAMES = 12       # 한 호흡 루프 프레임 수
BREATH_PERIOD_MS = 1600  # 한 호흡 주기(ms). 사람 idle 호흡은 1200~2500ms 권장
BREATH_AMPLITUDE = 0.03  # 세로 팽창 최대치(3%)
BREATH_WIDTH_RATIO = 0.35  # 가로 팽창 = 세로의 35% (가슴이 위로 부풀며 살짝 옆으로)

# 배경 제거
CHROMA_TOLERANCE = 110   # 크로마키 색상 거리 허용치(0~441). jpeg 압축 번짐 감안해 넉넉히
ALPHA_FLOOR = 8          # 이보다 옅은 알파는 0으로(잔여 후광/노이즈 제거)

EXPORT_GIF = False       # 웹 게임은 WebP만으로 충분. 필요 시 True (투명 GIF 별도 처리)
OUTPUT_DIR = Path("output")
FINAL_WEBP_DIR = OUTPUT_DIR / "webp"
MONSTER_JSON = Path(__file__).with_name("monster.json")

ART_STYLE = (
    "clean 2D game art, soft cel shading, chibi proportions, "
    "cute and adorable illustration style, rounded shapes, friendly expression, "
    "like a modern Pokémon-style sprite"
)

BG_COLORS = {"magenta": ("#FF00FF", (255, 0, 255)), "green": ("#00FF00", (0, 255, 0))}

PROMPT_TEMPLATE = """Create a single character sprite for a monster-raising game.

## Monster
{monster_spec}

## Requirements
- ONE character only, front-facing, full body visible
- Neutral idle resting pose, standing, arms relaxed
- Centered with a little margin around it, feet near the bottom
- {art_style}

## Background
- {bg_instruction}
"""

# 투명 배경 지원 여부를 판별하기 위한 프로브 프롬프트
TRANSPARENT_PROBE_PROMPT = (
    "A single simple red apple, centered, full object visible. "
    "Transparent background (PNG alpha), absolutely no background, "
    "no ground, no shadow, no floor."
)

_client = None


# ──────────────────────────────────────────────
# 몬스터 데이터 로드
# ──────────────────────────────────────────────
def _field(data: dict, *names: str):
    for name in names:
        if name in data:
            return data[name]
    return None


def _as_two_digit(value, field_name: str) -> str:
    try:
        number = int(value)
    except (TypeError, ValueError):
        raise ValueError(f"{field_name} 값은 정수여야 합니다: {value!r}") from None
    if number < 1:
        raise ValueError(f"{field_name} 값은 1 이상이어야 합니다: {number}")
    return f"{number:02d}"


def _normalize_monster(raw: dict, inherited: dict | None = None) -> dict:
    inherited = inherited or {}
    merged = {**inherited, **raw}
    monster = {
        "dex": _field(merged, "dex", "dex_no", "dexNo"),
        "step": _field(merged, "step", "stage"),
        "name": _field(merged, "name"),
        "spec": _field(merged, "spec", "prompt", "description"),
        "bg": _field(merged, "bg", "background"),
    }

    missing = [k for k, v in monster.items() if v in (None, "")]
    if missing:
        name = monster.get("name") or raw
        raise ValueError(f"monster.json 항목에 필수 필드가 없습니다({', '.join(missing)}): {name}")

    monster["dex_label"] = _as_two_digit(monster["dex"], "dex")
    monster["step_label"] = _as_two_digit(monster["step"], "step")
    monster["name"] = str(monster["name"])
    monster["spec"] = str(monster["spec"])
    monster["bg"] = str(monster["bg"])
    if monster["bg"] not in BG_COLORS:
        raise ValueError(f"bg는 {tuple(BG_COLORS)} 중 하나여야 합니다: {monster['bg']!r}")
    return monster


def load_monsters(path: Path = MONSTER_JSON) -> list[dict]:
    if not path.exists():
        raise FileNotFoundError(f"몬스터 JSON 파일을 찾을 수 없습니다: {path}")

    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict):
        entries = data.get("monsters") or data.get("monster_lines")
        if entries is None:
            entries = [data]
    elif isinstance(data, list):
        entries = data
    else:
        raise ValueError("monster.json 최상위는 배열 또는 객체여야 합니다")

    monsters: list[dict] = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError(f"monster.json 항목은 객체여야 합니다: {entry!r}")
        forms = entry.get("forms")
        if forms is None:
            monsters.append(_normalize_monster(entry))
            continue

        inherited = {k: v for k, v in entry.items() if k != "forms"}
        for form in forms:
            if not isinstance(form, dict):
                raise ValueError(f"forms 항목은 객체여야 합니다: {form!r}")
            monsters.append(_normalize_monster(form, inherited))

    return monsters


def monster_output_base(monster: dict) -> Path:
    basename = f"{monster['step_label']}_{monster['name']}"
    return OUTPUT_DIR / monster["dex_label"] / basename / basename


def final_webp_path(monster: dict) -> Path:
    return FINAL_WEBP_DIR / f"{monster['dex_label']}_{monster['step_label']}.webp"


# ──────────────────────────────────────────────
# 1) 생성: Gemini 3.1 Interactions API
# ──────────────────────────────────────────────
def load_env(path: str = ".env") -> None:
    """.env의 KEY=VALUE를 os.environ에 로드(기존 값은 덮어쓰지 않음)."""
    p = Path(path)
    if not p.exists():
        return
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def _api_key() -> str:
    load_env()  # 실행 위치의 .env를 자동 로드
    for var in ("GEMINI_API_KEY", "GOOGLE_API_KEY"):
        if os.environ.get(var):
            return os.environ[var]
    raise RuntimeError(
        "GEMINI_API_KEY 또는 GOOGLE_API_KEY가 없습니다 (.env 또는 환경변수 확인)"
    )


def _get_client():
    global _client
    if _client is None:
        from google import genai  # pip install google-genai
        _client = genai.Client(api_key=_api_key())
    return _client


def _extract_image_b64(interaction) -> str:
    """Interactions 응답에서 이미지 base64를 꺼낸다(편의 프로퍼티 → steps 순회)."""
    oi = getattr(interaction, "output_image", None)
    if oi is not None and getattr(oi, "data", None):
        return oi.data
    for step in getattr(interaction, "steps", None) or []:
        if getattr(step, "type", None) != "model_output":
            continue
        for block in getattr(step, "content", None) or []:
            if getattr(block, "type", None) == "image" and getattr(block, "data", None):
                return block.data
    raise RuntimeError("응답에 이미지가 없음 (텍스트만 반환됨)")


def generate(prompt: str, retries: int = 3) -> Image.Image:
    """나노바나나2로 이미지 1장 생성. 알파 보존을 위해 convert하지 않고 원본 모드 유지."""
    client = _get_client()
    for attempt in range(1, retries + 1):
        try:
            interaction = client.interactions.create(
                model=MODEL,
                input=prompt,
                response_format={
                    "type": "image",
                    "mime_type": MIME_TYPE,
                    "aspect_ratio": ASPECT_RATIO,
                    "image_size": IMAGE_SIZE,
                },
            )
            data = _extract_image_b64(interaction)
            return Image.open(BytesIO(base64.b64decode(data)))
        except Exception as e:
            if attempt == retries:
                raise
            print(f"  ⚠ 생성 실패({e}), {attempt}/{retries} 재시도...")
            time.sleep(3 * attempt)


# ──────────────────────────────────────────────
# 2) 배경 처리
# ──────────────────────────────────────────────
def has_real_transparency(img: Image.Image, min_fraction: float = 0.05) -> bool:
    """이미지에 '의미 있는' 투명 영역이 있는지(=투명 배경 출력 성공) 판별."""
    if img.mode not in ("RGBA", "LA", "PA") and "transparency" not in img.info:
        return False
    alpha = img.convert("RGBA").getchannel("A")
    near_transparent = sum(alpha.histogram()[:16])  # 알파 0~15인 픽셀 수
    return near_transparent / (img.width * img.height) >= min_fraction


def clean_alpha(rgba: Image.Image) -> Image.Image:
    """아주 옅은 알파를 0으로 눌러 잔여 후광/사각 노이즈를 제거."""
    arr = np.asarray(rgba, dtype=np.uint8).copy()
    a = arr[..., 3]
    a[a < ALPHA_FLOOR] = 0
    arr[..., 3] = a
    return Image.fromarray(arr, "RGBA")


def detect_key_color(img: Image.Image, border: float = 0.04) -> tuple[int, int, int]:
    """이미지 테두리(배경으로 가정)의 중앙값으로 실제 배경 키색을 추정.

    AI 모델은 'green'을 (0,255,0)이 아니라 (16,220,51)처럼 근사색으로 그리므로,
    키색을 고정하지 않고 실측 배경색을 뽑아야 크로마키가 안정적이다.
    """
    arr = np.asarray(img.convert("RGB"))
    h, w, _ = arr.shape
    b = max(2, int(min(h, w) * border))
    edges = np.concatenate(
        [
            arr[:b].reshape(-1, 3),
            arr[-b:].reshape(-1, 3),
            arr[:, :b].reshape(-1, 3),
            arr[:, -b:].reshape(-1, 3),
        ]
    )
    return tuple(int(v) for v in np.median(edges, axis=0))


def remove_bg_chroma(img: Image.Image, key_rgb: tuple[int, int, int]) -> Image.Image:
    """단색 배경 크로마키(numpy 벡터화 + despill). 경계에 부드러운 알파를 만든다."""
    arr = np.asarray(img.convert("RGB"), dtype=np.float32)
    r0, g0, b0 = arr[..., 0], arr[..., 1], arr[..., 2]
    key = np.array(key_rgb, dtype=np.float32)
    dist = np.sqrt(((arr - key) ** 2).sum(axis=-1))

    soft = CHROMA_TOLERANCE * 0.5
    alpha = np.clip((dist - soft) / (CHROMA_TOLERANCE - soft), 0.0, 1.0)  # 경계 램프
    alpha[dist < soft] = 0.0
    alpha[dist >= CHROMA_TOLERANCE] = 1.0

    # despill: 키 색 성분을 다른 채널 최대치로 눌러 가장자리 색번짐 제거
    kr, kg, kb = key_rgb
    r, g, b = r0, g0, b0
    if kg >= kr and kg >= kb:            # green 키
        g = np.minimum(g0, np.maximum(r0, b0))
    elif kr >= kg and kb >= kg:          # magenta 키(R·B 높음)
        r = np.minimum(r0, np.maximum(g0, b0))
        b = np.minimum(b0, np.maximum(g0, r0))

    rgb = np.stack([r, g, b], axis=-1)
    out = np.dstack([rgb, alpha * 255.0]).astype(np.uint8)
    return clean_alpha(Image.fromarray(out, "RGBA"))


def prepare_base_sprite(
    img: Image.Image, mode: str, key_rgb: tuple[int, int, int] | None
) -> Image.Image:
    """배경 제거 후 알파 기준으로 타이트하게 크롭한 기준 스프라이트를 반환."""
    if mode == "transparent":
        rgba = clean_alpha(img.convert("RGBA"))
    else:
        assert key_rgb is not None, "chroma 모드에는 key_rgb가 필요합니다"
        rgba = remove_bg_chroma(img, key_rgb)

    bbox = rgba.getchannel("A").getbbox()  # 알파(불투명 영역) 기준 크롭
    if not bbox:
        raise RuntimeError("배경 제거 후 남은 픽셀이 없음 — 배경색/허용치 확인 필요")
    return rgba.crop(bbox)


# ──────────────────────────────────────────────
# 3) 숨쉬기 프레임 합성 (하단 고정 스쿼시/스케일)
# ──────────────────────────────────────────────
def make_breathing_frames(sprite: Image.Image) -> list[Image.Image]:
    """기준 스프라이트 1장 → 하단 고정 호흡 애니메이션 프레임들."""
    canvas = OUTPUT_SIZE
    peak = 1.0 + BREATH_AMPLITUDE
    # 최대 팽창(peak) 프레임까지 캔버스 안에 들어오도록 기준 크기를 잡는다
    max_h = canvas * BODY_FILL / peak
    max_w = canvas * BODY_FILL
    s = min(max_w / sprite.width, max_h / sprite.height)
    base = sprite.resize(
        (max(1, round(sprite.width * s)), max(1, round(sprite.height * s))), RESAMPLE
    )

    frames: list[Image.Image] = []
    for i in range(BREATH_FRAMES):
        t = i / BREATH_FRAMES  # 0..1 (마지막이 0으로 복귀 → 매끄러운 루프)
        # 0 → A → 0 으로만 움직이는 호흡(중립에서 팽창했다 복귀; 수축 안 함)
        e = BREATH_AMPLITUDE * (1.0 - math.cos(2.0 * math.pi * t)) / 2.0
        sy = 1.0 + e
        sx = 1.0 + e * BREATH_WIDTH_RATIO
        w = max(1, round(base.width * sx))
        h = max(1, round(base.height * sy))
        scaled = base.resize((w, h), RESAMPLE)

        frame = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        x = (canvas - w) // 2
        y = canvas - h - BOTTOM_MARGIN  # 하단 고정(발 위치 불변)
        frame.paste(scaled, (x, y), scaled)  # 알파를 마스크로 합성
        frames.append(frame)
    return frames


# ──────────────────────────────────────────────
# 4) 조립: 애니메이션 WebP (+ 옵션 투명 GIF)
# ──────────────────────────────────────────────
def save_transparent_gif(frames: list[Image.Image], path: Path, duration: int) -> None:
    """RGBA 프레임 → 투명 인덱스를 가진 애니메이션 GIF(1비트 알파)."""
    pal_frames = []
    for f in frames:
        alpha = f.getchannel("A")
        p = f.convert("RGB").quantize(colors=255)  # 팔레트 255색, 255번은 투명용으로 예약
        transparent_mask = alpha.point(lambda a: 255 if a < 128 else 0)
        p.paste(255, transparent_mask)
        pal_frames.append(p)
    pal_frames[0].save(
        path,
        save_all=True,
        append_images=pal_frames[1:],
        duration=duration,
        loop=0,
        transparency=255,
        disposal=2,
    )


def assemble(frames: list[Image.Image], out_base: Path, duration: int) -> None:
    out_base.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        out_base.with_suffix(".webp"),
        save_all=True,
        append_images=frames[1:],
        duration=duration,
        loop=0,
        lossless=True,   # 8비트 알파 무손실 → 가장자리 깨끗
        method=6,
    )
    if EXPORT_GIF:
        save_transparent_gif(frames, out_base.with_suffix(".gif"), duration)


# ──────────────────────────────────────────────
# 파이프라인
# ──────────────────────────────────────────────
def build_prompt(monster: dict, mode: str) -> str:
    if mode == "transparent":
        bg = (
            "Transparent background (PNG alpha), absolutely no background, "
            "no ground, no shadow, no floor, no glow, no text."
        )
    else:
        bg_hex, _ = BG_COLORS[monster["bg"]]
        bg = (
            f"Solid flat {monster['bg']} background ({bg_hex}), fully uniform, "
            f"no gradient, no shadow, no glow, no outline, no text, no grid."
        )
    return PROMPT_TEMPLATE.format(
        monster_spec=monster["spec"], art_style=ART_STYLE, bg_instruction=bg
    )


def resolve_mode() -> str:
    """BG_MODE에 따라 실제 배경 처리 모드를 결정(auto면 투명배경 지원을 1회 프로브)."""
    if BG_MODE in ("transparent", "chroma"):
        print(f"■ 배경 모드 고정: {BG_MODE}\n")
        return BG_MODE

    # auto: 투명 출력은 알파(png)가 필요한데 현재 API는 jpeg-only → 프로브 없이 chroma로 확정.
    if MIME_TYPE == "image/jpeg":
        print("■ auto: 출력이 jpeg(알파 불가)이므로 크로마키로 결정 (프로브 생략)\n")
        return "chroma"

    print("■ 투명 배경 지원 테스트(프로브) 중...")
    try:
        probe = generate(TRANSPARENT_PROBE_PROMPT)
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        probe.save(OUTPUT_DIR / "_probe.png")
        supported = has_real_transparency(probe)
    except Exception as e:
        print(f"  프로브 실패({e}) → 크로마키로 폴백\n")
        return "chroma"

    print(
        "  → 투명 배경 지원됨 ✔ (transparent 모드)\n"
        if supported
        else "  → 투명 배경 미지원 ✘ (크로마키 모드로 폴백)\n"
    )
    return "transparent" if supported else "chroma"


def process(monster: dict, mode: str) -> None:
    name = monster["name"]
    out_base = monster_output_base(monster)
    workdir = out_base.parent
    workdir.mkdir(parents=True, exist_ok=True)

    print(f"▶ {monster['dex_label']}/{monster['step_label']} {name}: 스프라이트 생성...")
    raw = generate(build_prompt(monster, mode))
    raw.save(workdir / "raw.png")

    key_rgb = None
    if mode == "chroma":
        key_rgb = detect_key_color(raw)  # 고정색이 아니라 실측 배경색으로 키잉
        nominal = BG_COLORS[monster["bg"]][1]
        d = sum((a - b) ** 2 for a, b in zip(key_rgb, nominal)) ** 0.5
        print(f"   감지 배경 키색 RGB={key_rgb} (요청 {monster['bg']} 대비 거리 {d:.0f})")
        if d > 160:  # 요청 색과 너무 다르면 모델이 배경을 무시했을 가능성
            print("   ⚠ 감지색이 요청 배경과 크게 다름 — raw.png 배경 확인 권장")
    sprite = prepare_base_sprite(raw, mode, key_rgb)
    sprite.save(workdir / "sprite.png")

    print(f"▶ {name}: 숨쉬기 프레임 합성({BREATH_FRAMES}장)...")
    frames = make_breathing_frames(sprite)
    for i, f in enumerate(frames, 1):
        f.save(workdir / f"frame_{i:02d}.png")

    duration = max(20, round(BREATH_PERIOD_MS / BREATH_FRAMES))
    assemble(frames, out_base, duration)

    final_path = final_webp_path(monster)
    final_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(out_base.with_suffix(".webp"), final_path)
    print(f"✔ {name}: {out_base.with_suffix('.webp')} 완료")
    print(f"   최종 WebP 복사: {final_path}\n")


def main() -> None:
    mode = resolve_mode()
    monsters = load_monsters()
    for m in monsters:
        try:
            process(m, mode)
        except Exception as e:
            print(f"✘ {m['name']} 실패: {e}\n")


if __name__ == "__main__":
    main()
