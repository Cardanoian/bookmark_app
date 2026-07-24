# 몬스터 숨쉬기 애니메이션 파이프라인 (B안)

몬스터 스프라이트를 **한 장만** AI로 생성하고, 숨쉬기(idle) 애니메이션은 **코드로 합성**하는 도구.
Gemini 3.1 Flash Image(나노바나나2, Interactions API) 사용.

```
생성(1콜, jpeg) → 배경 자동감지 크로마키 → 하단 고정 스쿼시/스케일 N프레임 → 애니메이션 WebP
```

## 왜 B안(1프레임 + 코드 호흡)인가

- **일관성 100%**: 같은 픽셀을 코드로 변형하므로 프레임 간 캐릭터 모핑/떨림이 없음
- **비용 최소**: 몬스터당 API 호출 1회 (프레임을 AI로 여러 장 뽑지 않음)
- **제어 자유**: 호흡 속도·프레임 수·진폭을 코드 상수로 조정

## ⚠️ 실측으로 확정된 제약 (중요)

1. **현재 Interactions API / `gemini-3.1-flash-image`는 `image/jpeg` 출력만 지원** (`image/png`은 400 에러).
2. jpeg는 알파 채널이 없으므로 **투명 배경 직접 출력은 불가능** → **크로마키가 필수**.
3. 모델은 `green`을 순수 (0,255,0)이 아니라 (17,220,50)처럼 **근사색**으로 그림.
   그래서 키색을 고정하지 않고 **이미지 테두리에서 실제 배경색을 자동 감지**(`detect_key_color`)해서 키잉한다.
   → 이 자동감지 덕분에 배경이 깔끔히 제거되고 가장자리 색번짐(despill)도 억제됨.

> 추후 png/투명 배경을 지원하는 모델이 나오면 `BG_MODE="transparent"` + `MIME_TYPE="image/png"`로 전환 가능(코드에 경로 유지).

## 설치

```bash
pip install -r script/requirements.txt   # google-genai pillow numpy
```

## API 키

프로젝트 루트 `.env`에 저장하면 자동 로드된다(`GOOGLE_API_KEY` 또는 `GEMINI_API_KEY` 모두 인식).

```
GOOGLE_API_KEY=발급받은키
```

## 실행

```bash
python script/monster_sprite_pipeline.py
```

`monsters` 리스트를 순서대로 처리하며, 한 마리가 실패해도 다음으로 넘어간다.

## 출력

```
output/불꽃도롱뇽/
├── raw.png             # 원본 생성 이미지(디버깅용)
├── sprite.png          # 배경 제거·크롭된 기준 스프라이트
├── frame_01.png ...    # 합성된 숨쉬기 프레임
└── 불꽃도롱뇽.webp      # 애니메이션 WebP ← 웹 게임에서 이걸 사용 (<img>만으로 무한 재생)
```

## 몬스터 추가

`monsters` 리스트에 딕셔너리 추가:

```python
{
    "name": "번개다람쥐",
    "spec": "A small electric squirrel monster. Fluffy yellow fur, "
            "lightning-bolt tail, rosy cheeks, big sparkling eyes. Hyperactive.",  # 영어 권장
    "bg": "magenta",   # 크로마키 배경. 몬스터 색과 겹치지 않게 선택
}
```

`bg` 선택: 빨강·분홍·주황 몬스터 → `"green"`, 초록·청록 → `"magenta"`.
(실제 키잉은 자동 감지색으로 하지만, 프롬프트에 어떤 스크린을 그릴지 지시하는 값이므로 겹치지 않게 고르는 게 중요.)

## 주요 설정값 (스크립트 상단)

| 상수 | 기본값 | 설명 |
|---|---|---|
| `MODEL` | `gemini-3.1-flash-image` | 프리뷰면 `-preview` 접미사 확인 |
| `MIME_TYPE` | `image/jpeg` | ★ 현재 API는 jpeg만 허용 |
| `ASPECT_RATIO` / `IMAGE_SIZE` | `1:1` / `2K` | 단일 몬스터·다운샘플용 여유 해상도 |
| `BG_MODE` | `chroma` | `chroma` / `transparent` / `auto` |
| `CHROMA_TOLERANCE` | `110` | jpeg 번짐 감안한 색상 거리 허용치 |
| `OUTPUT_SIZE` | `256` | 최종 프레임 한 변 |
| `BREATH_FRAMES` | `12` | 한 호흡 루프 프레임 수 |
| `BREATH_PERIOD_MS` | `1600` | 한 호흡 주기(ms) |
| `BREATH_AMPLITUDE` | `0.03` | 세로 팽창 최대 3% |
| `EXPORT_GIF` | `False` | WebP만으로 충분. 필요 시 True(투명 GIF 별도 처리) |

## 트러블슈팅

| 증상 | 해결 |
|---|---|
| 배경이 안 지워짐 | `raw.png` 배경이 균일 단색인지 확인. 모델이 배경을 무시하고 풍경/그림자를 넣으면 실패 → 프롬프트의 배경 지시 강화, `bg` 변경 |
| "감지색이 요청 배경과 크게 다름" 경고 | 모델이 요청 배경색을 무시함 → 프롬프트 강화 또는 재생성 |
| 몬스터 가장자리 색번짐 | despill이 처리하지만 심하면 `CHROMA_TOLERANCE` 조정 |
| `image/png ... not supported` 400 | `MIME_TYPE`을 `image/jpeg`로(현재 유일 지원) |
| 호흡이 너무 미묘/과함 | `BREATH_AMPLITUDE`, `BREATH_PERIOD_MS` 조정 |
| WebP 프레임 수가 설정보다 적음 | 정상. 3% 진폭 반올림상 중립 구간 프레임이 병합되며, **재생시간은 무손실 보존**됨 |

## 게임에 넣기 (Rails)

```erb
<%= image_tag "monsters/#{@monster.slug}.webp", alt: @monster.name, class: "monster-sprite" %>
```

WebP 애니메이션은 별도 JS 없이 `<img>`만으로 무한 루프 재생된다.
생성물을 `app/assets/images/monsters/`에 넣으면 끝.
