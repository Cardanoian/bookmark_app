# script/ — 몬스터 스프라이트 생성 파이프라인 (오프라인 에셋 도구, Python)

반려 몬스터의 애니메이션 스프라이트(숨쉬기 WebP)를 만드는 **오프라인 에셋 생성 도구**다. Gemini 3.1 Flash Image(나노바나나2, Interactions API)로 스프라이트를 **단 한 장**만 생성한 뒤, 숨쉬기(idle breathing)는 코드로 합성한다(생성 1콜 → 배경 크로마키 → 하단 고정 스쿼시/스케일 N프레임 → 애니메이션 WebP). **Rails 앱 런타임과 완전히 분리**되어 있으며, 앱은 여기서 만든 산출물(`app/assets/images/monsters/`)만 사용한다.

## 파일
- `monster_sprite_pipeline.py` — 핵심 스크립트. `monster.json`을 읽어 몬스터별로 이미지 생성→배경 자동감지 크로마키 제거→호흡 프레임 합성→WebP 저장까지 전 과정을 수행. (모델은 jpeg만 출력하므로 투명 배경 대신 크로마키가 필수)
- `monster.json` — 입력 데이터. 파이프라인이 실제로 처리하는 몬스터 스펙(dex·step·name·spec·bg) 목록.
- `monster_all.json` — 전체 도감 원본 데이터(72폼 참조용).
- `requirements.txt` — Python 의존성: `google-genai`·`pillow`·`numpy`.
- `README_monster_sprite.md` — 도구 상세 가이드(원리·설치·실행·설정값·트러블슈팅·게임 삽입법).
- `.env` — API 키(`GOOGLE_API_KEY`/`GEMINI_API_KEY`) 저장. **비밀 파일 — 열지 말 것.**

생성물인 `output/`(스프라이트·프레임·WebP), `.venv/`, `__pycache__/`는 도구가 만들어 내는 산출물이라 여기서 다루지 않는다.

## 패턴·규칙
- 설치·실행: `pip install -r script/requirements.txt` 후 `python script/monster_sprite_pipeline.py`. 프로젝트 루트 `.env`가 자동 로드된다.
- 튜닝 상수(모델·MIME·크로마 허용치·호흡 프레임/주기/진폭 등)는 스크립트 상단에 모여 있다. 변경 근거는 `README_monster_sprite.md` 참조.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
