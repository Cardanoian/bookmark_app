# script/ — 오프라인 생성 도구 (몬스터 스프라이트 Python + 도서 카탈로그 Ruby)

Rails 앱 런타임에 실시간으로 얽히지 않는 **오프라인 산출물 생성 도구** 모음이다. 스프라이트 파이프라인은
완전 독립된 Python 스크립트, 도서 카탈로그 도구는 `bin/rails runner`로 Rails 환경(AR 모델·`Faraday` 등)을
빌려 쓰는 Ruby 스크립트다. 둘 다 사람이 필요할 때 수동 실행하는 생성기이며, 앱은 산출물만
(`app/assets/images/monsters/`·`db/seeds/elementary_books.tsv`) 소비한다.

## 몬스터 스프라이트 파이프라인 (Python)

반려 몬스터의 애니메이션 스프라이트(숨쉬기 WebP)를 만드는 도구다. Gemini 3.1 Flash Image(나노바나나2,
Interactions API)로 스프라이트를 **단 한 장**만 생성한 뒤, 숨쉬기(idle breathing)는 코드로 합성한다
(생성 1콜 → 배경 크로마키 → 하단 고정 스쿼시/스케일 N프레임 → 애니메이션 WebP). **Rails 앱과 완전히
분리**되어 있으며, 앱은 여기서 만든 산출물(`app/assets/images/monsters/`)만 사용한다.

### 파일
- `monster_sprite_pipeline.py` — 핵심 스크립트. `monster.json`을 읽어 몬스터별로 이미지 생성→배경 자동감지 크로마키 제거→호흡 프레임 합성→WebP 저장까지 전 과정을 수행. (모델은 jpeg만 출력하므로 투명 배경 대신 크로마키가 필수)
- `monster.json` — 입력 데이터. 파이프라인이 실제로 처리하는 몬스터 스펙(dex·step·name·spec·bg) 목록.
- `monster_all.json` — 전체 도감 원본 데이터(72폼 참조용).
- `requirements.txt` — Python 의존성: `google-genai`·`pillow`·`numpy`.
- `README_monster_sprite.md` — 도구 상세 가이드(원리·설치·실행·설정값·트러블슈팅·게임 삽입법).
- `.env` — API 키(`GOOGLE_API_KEY`/`GEMINI_API_KEY`) 저장. **비밀 파일 — 열지 말 것.**

생성물인 `output/`(스프라이트·프레임·WebP), `.venv/`, `__pycache__/`는 도구가 만들어 내는 산출물이라 여기서 다루지 않는다.

### 패턴·규칙
- 설치·실행: `pip install -r script/requirements.txt` 후 `python script/monster_sprite_pipeline.py`. 프로젝트 루트 `.env`가 자동 로드된다.
- 튜닝 상수(모델·MIME·크로마 허용치·호흡 프레임/주기/진폭 등)는 스크립트 상단에 모여 있다. 변경 근거는 `README_monster_sprite.md` 참조.

## 도서 카탈로그 도구 (Ruby)

초등 전학년 도서 카탈로그(`db/seeds/elementary_books.tsv`)를 만들고 다듬는 오프라인 도구. `bin/rails
runner`로 Rails 환경(AR 모델 `Book`, `Library::Data4libraryService::BASE_URL` 등)을 빌려 쓰지만, `script/`는
Zeitwerk 오토로드 경로 밖이라 스크립트끼리는 `require_relative`로 명시 로드한다. 네트워크 호출·파일
쓰기는 산출물 TSV 에만 하며 앱 DB는 건드리지 않는다(TSV 적재는 별도로 `lib/tasks/books.rake`의
`books:seed_full`이 담당 — `lib/tasks/CLAUDE.md` 참고).

### 파일
- `build_elementary_books_tsv.rb` — 카탈로그 생성 메인. 정보나루(data4library) 학년별(a8/a10/a12) 인기대출 API + NLCY(국립어린이청소년도서관) 사서 추천 목록 + 앱 큐레이션 `Book` 레코드를 병합해 `db/seeds/elementary_books.tsv`(8,502행, 탭 구분)를 만든다. `BOOKS_FROM`/`BOOKS_TO`/`BOOKS_LIMIT` ENV로 조회 기간·밴드별 상한을 조정. KDC 대분류/NLCY 주제를 10개 장르로 매핑하고, 널리 알려진 제목·저자 패턴(`CLASSIC_TITLES`/`CLASSIC_AUTHOR_PATTERN`)에 매칭되는 경우만 고전으로 보수적으로 표시한다(추측 대신 미상은 "검토필요"로 남김). 실행: `bin/rails runner script/build_elementary_books_tsv.rb`.
- `book_genre_inference.rb` — `Books::GenreInference`. 이미 장르가 분류된 이웃 도서들에서 **가중 n-gram(제목 2·3-gram·낱말·시리즈명·저자·출판사) 코사인 유사도**로 장르를 추론하는 순수 PORO(외부 API 호출·KDC 코드 발명 없음). 규칙은 2티어(`DECISIVE_GENRE_RULES`=고정밀 신호로 kNN 신뢰도 무관하게 우선, `STRONG_GENRE_RULES`=넓은 주제어라 유사도 신뢰도가 낮을 때만 우선)이며 app 판본과 동기화한다. `build_elementary_books_tsv.rb`·`fill_missing_book_genres.rb` 공용.
- `fill_missing_book_genres.rb` — TSV의 공란/미분류 `genre` 행만 `Books::GenreInference`로 채우는 후처리 스크립트(`bin/rails runner`). **기존에 채워진 장르값은 절대 바꾸지 않는다**. 프로젝트 큐레이션 행(`selection_type` 에 `project_curated` 포함)은 추론 대신 "문학"으로 고정 확신 처리. 결과는 Tempfile 에 써서 `File.rename`으로 원자적으로 교체한다. 실행: `bin/rails runner script/fill_missing_book_genres.rb`(`BOOKS_TSV` ENV로 대상 파일 교체 가능).

### 패턴·규칙
- 세 스크립트 모두 오프라인 생성기다 — 실행은 사람이 수동으로(`bin/rails runner`), 산출물 TSV 의 DB 적재는 `books:seed_full`이 별도로 담당한다.
- 산출물 `db/seeds/elementary_books.tsv`는 git 커밋 대상이다(`db/CLAUDE.md` seeds/ 참고).

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
