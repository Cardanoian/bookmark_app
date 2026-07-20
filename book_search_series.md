# 도서 검색 "중복" 이슈 — 조사 결과 및 작업 계획

> 작성일: 2026-07-20 · 상태: **조사 완료, 구현 미착수**
> 다음 세션에서 이 문서만 읽고 이어서 작업할 수 있도록 정리함.

---

## Context — 왜 이 작업을 하는가

학생이 독후감·게임을 위해 책을 검색하면(예: "삼국지") 자동완성 드롭다운에
**제목·저자가 글자 하나까지 똑같은 항목이 20줄** 나온다. 사용자에게는 명백한 버그로 보이고,
초등학생이 어떤 항목을 골라야 할지 판단할 수 없다.

조사 결과 **데이터 중복이 아니라 표시(display) 문제**로 판명되었다. 시리즈 별권이
각각 별개의 책인데 화면에서 구분할 정보가 전혀 없는 것이다.

---

## ✅ 완료된 부분 (조사·원인 규명·방향 확정)

### 1. 근본 원인 규명 — 완료

**결론: DB 중복 레코드는 0건이다. 시리즈 별권이 구분 없이 나열되는 것이다.**

개발 DB(`storage/development.sqlite3`) 실측:

| 항목 | 값 |
|---|---|
| `COUNT(*) FROM books` | 8,650 |
| `COUNT(DISTINCT isbn)` | **8,650** (완전 일치) |
| isbn 중복 그룹 | **0건** |
| isbn NULL 또는 빈 문자열 | **0건** |
| DISTINCT title | 5,848 |
| title+author 중복 그룹에 속한 행 | 3,366행 |

`db/schema.rb:137-152` — `books.isbn` 에 **unique index + NOT NULL + `length(isbn)=13 AND isbn NOT GLOB '*[^0-9]*'` CHECK 제약**이
걸려 있어 동일 ISBN 중복행은 구조적으로 불가능하다.

"삼국지" 포함 도서 57건은 **전부 ISBN이 서로 다르다**. 대표 사례:
- `설민석의 삼국지 대모험` 26행 = 1권 ~ 26권 (ISBN 9791193031544, 9791193031551, 9791193031568 …)
- `(주석으로 쉽게 읽는) 고정욱 삼국지` 3행 (연속 ISBN …781 / …798 / …804)

title+author 중복 상위는 전부 학습만화 시리즈물이다:
마법천자문 52권, 설민석의 한국사 대모험 52권, 그리스 로마 신화 49권, 내일은 발명왕 44권.

### 2. 원인 체인 특정 — 완료

중복처럼 **보이게** 만드는 4개 지점을 순서대로 특정했다.

| # | 위치 | 문제 |
|---|---|---|
| **1** | `db/seeds/elementary_books.tsv` → `lib/tasks/books.rake:38-78` | TSV에 **`volume` 컬럼이 존재**(헤더 9번째 필드, 값 예: 21, 22, 23)하는데 `books` 테이블에 해당 컬럼이 없어 rake가 값을 버린다. `books.rake:88` 주석이 "Dropped columns … were not saved"로 명시 |
| **2** | `app/controllers/books_controller.rb:53-56` | 자동완성 JSON이 `{id, title, author, cover_url, genre, classic}` 만 반환. **`publisher`조차 없고 권차도 없다** → UI에서 구분할 데이터 자체가 없음 |
| **3** | `app/controllers/books_controller.rb:49-52` | `.order(:title).limit(20)` — 그룹핑·`uniq` 없이 정렬만 하므로 **한 시리즈가 드롭다운 20줄을 통째로 점유** |
| **4** | `app/javascript/controllers/book_search_controller.js:102` | `[item.author, item.publisher].filter(Boolean).join(" · ")` — 로컬 결과엔 publisher가 없어 **항상 undefined**. 저자만 렌더됨 |

TSV 원본 확인 (같은 제목·저자·출판사, ISBN·volume만 다름):
```
EB00190  설민석의 삼국지 대모험  원작: 나관중 ;만화: 스튜디오 담  Dankkum i  9791193031544  … volume=21
EB00192  설민석의 삼국지 대모험  원작: 나관중 ;만화: 스튜디오 담  Dankkum i  9791193031551  … volume=22
EB00236  설민석의 삼국지 대모험  원작: 나관중 ;만화: 스튜디오 담  Dankkum i  9791193031568  … volume=23
```

### 3. 오진 배제 — 완료

조사 중 다음 가설들을 검증하고 **모두 기각**했다. 다시 조사할 필요 없다.

- ❌ **프런트엔드 append 버그 아님** — `book_search_controller.js:77` 이 `replaceChildren(...)` 로 전체 교체하며,
  25-30행에 `clearTimeout` + 300ms 디바운스가 정상 작동한다. 요청이 겹쳐도 목록이 누적되지 않는다.
  (다만 `AbortController` 부재로 "낡은 응답이 최신을 덮어쓰는" 경합은 이론상 가능 — 이번 증상과는 무관한 별건)
- ❌ **시드 태스크가 중복 생성하는 구조 아님** — `books.rake:64` 가 `Book.find_or_initialize_by(isbn: isbn)` 기반이라 멱등.
  게다가 unique index가 DB 레벨에서 차단한다.
- ❌ **여러 소스 merge 문제 아님** — `Books::SearchService#call` 은 원격/로컬을 **배타적 either-or** 로 쓴다(병합 없음).
  `Library::Data4libraryService` 는 자동완성 경로에 전혀 관여하지 않는다.
- ❌ **`books:deduplicate_isbn` 태스크로 해결 불가** — `Books::Deduplicator` 는 ISBN 정규화 동일성 또는
  "ISBN 공란 그림자" 그룹만 다룬다. 현재 DB 기준 **대상 0건**이라 실행해도 증상이 그대로다.

> ⚠️ **절대 하지 말 것: 중복 삭제(DELETE)**
> 실제로 서로 다른 책(별권)이므로 삭제하면 카탈로그가 소실되고 `reports.book_id` 링크가 끊긴다.

### 4. 영향 범위 파악 — 완료

자동완성은 **공용 계약**이라 소비처가 많다. 계약 변경 시 전부 확인 필요:

- 공용 파셜: `app/views/books/_autocomplete_field.html.erb` (96-97행에 `<ul data-book-search-target="results">`)
- 소비처:
  - `app/views/reading_activities/show.html.erb:17-18` (독서활동, `mode: strict`)
  - `app/views/games/catalog/index.html.erb:7-27` (**파셜 미사용 인라인** — 별도 수정 필요)
  - `app/views/reports/_book_chooser.html.erb:12-22`
  - `app/views/reports/_form.html.erb:28-39`
  - `app/views/reports/_photo_capture.html.erb:11-16`
  - `app/views/books/index.html.erb:9-16`
  - teacher quizzes / missions 폼들
- 라우트 (`config/routes.rb:57` 부근) — 3개 액션의 역할이 다름:
  - `get :search` → 네이버 + 로컬 폴백 (독후감용)
  - `get :autocomplete` → **로컬 카탈로그 전용, 이번 증상의 경로**
  - `get :remote_search` → 🔍 버튼 전용 네이버
- 기존 테스트가 autocomplete JSON 키 집합을 고정하고 있음 (`test/` 하위, 41행 근처) → 계약 변경 시 깨짐

### 5. 수정 방향 확정 (사용자 결정) — 완료

**A. 시리즈 접기 → 2단계 선택**
자동완성은 title+author 기준 **대표 1행**만 표시하고 `전 26권` 배지를 단다.
학생이 그 항목을 고르면 **권 선택 단계**가 뜬다. 단권 책은 기존처럼 바로 선택되어야 한다.

```
설민석의 삼국지 대모험  [전 26권]
  원작: 나관중 ;만화: 스튜디오 담
(주석으로 쉽게 읽는) 고정욱 삼국지  [전 3권]
  원작: 나관중 ;고정욱 평역
문해력 평정 천하통일 삼국지  [전 12권]
```

**B. volume 컬럼 추가 + 시드 재실행으로 백필**
`books` 에 volume 컬럼을 추가하고 `books.rake` 가 TSV의 volume을 적재하도록 고친 뒤
`bin/rails books:seed_full` 재실행. 이 태스크는 `find_or_initialize_by(isbn:)` 기반 멱등이라
**기존 8,650행이 제자리 UPDATE 되고 `reports.book_id` 링크가 전부 보존된다.**

---

## ⬜ 해야 할 부분

### 0. 선행 — 미해결 설계 질문 (구현 전 결정 필요)

상세 구현 설계는 **아직 하지 않았다** (Plan 에이전트 실행 전 중단). 다음을 먼저 정해야 한다.

1. **그룹핑 쿼리 설계**
   SQLite에서 title+author 그룹핑하며 대표 1행의 `id` 와 권수 `COUNT(*)` 를 함께 얻는 방법.
   - 윈도우 함수 vs `GROUP BY` + `MIN(id)` vs 2단 조회 — 어느 쪽?
   - 8,650행 + `LIKE '%term%'` 풀스캔에서 성능 수용 가능한가? 인덱스 추가 필요한가?
     (현재 `index_books_on_title` non-unique 인덱스는 있으나 선행 `%` 라 무용)
   - 대표행 선정 기준: volume 최소? id 최소? (정렬 안정성 확보 필요)

2. **JSON 계약 변경**
   - 추가 필드 후보: `volume`, `publisher`, `series_count`, `group_key`
   - 기존 소비처가 안 깨지는 하위호환 형태인가?
   - 권 목록을 **첫 응답에 통째로** 실을지 vs **별도 엔드포인트**(예: `GET /books/volumes?title=&author=`)를 팔지
     — 26권 페이로드 크기를 따져 판단

3. **2단계 UI 상호작용**
   - 드롭다운 내 "드릴다운"(뒤로가기 포함) vs 별도 모달 — **초등학생 사용자**임을 고려
   - Stimulus 컨트롤러 내 상태 관리 방식
   - 키보드 접근성 · 모바일 터치
   - 기존 `mode: strict`(등록 도서만 허용)와의 상호작용

4. **마이그레이션 상세**
   - `volume` 컬럼 타입: integer? string? (TSV에 순수 숫자만 있는지 확인 필요, 없는 행은 NULL)
   - 인덱스 필요 여부
   - `category: searched` 행(네이버 검색 캐시)은 volume이 NULL인데 그룹핑에서 어떻게 처리?

5. **`books.rake` 수정 위치**
   기존 비파괴 갱신 패턴(`book.publisher = publisher if publisher`, rake 71-77행)을 따라
   volume을 대입할 위치와 파싱 방법 결정. 88행의 "Dropped columns" 주석도 갱신.

### 1. 구현 작업 목록

- [ ] **마이그레이션** — `db/migrate/*_add_volume_to_books.rb` 생성, `books.volume` 추가
- [ ] **`lib/tasks/books.rake`** — TSV `volume` 컬럼 읽어 대입 (비파괴 갱신 패턴 준수), 88행 주석 갱신
- [ ] **`bin/rails books:seed_full` 재실행** — 기존 8,650행 제자리 백필 검증
- [ ] **`app/controllers/books_controller.rb#autocomplete`** (43-57행) — 그룹핑 쿼리 + JSON 계약 확장
- [ ] **권 목록 엔드포인트** (별도 엔드포인트로 결정 시) — 라우트 + 액션 + 정책(`search?` 재사용 가능)
- [ ] **`app/javascript/controllers/book_search_controller.js`** — 2단계 드릴다운 상태·렌더·선택 로직
  - `itemElement()` 에 시리즈 배지 추가 (기존 `badge()` / `badgeElements()` 헬퍼 재사용)
  - `select()` 분기: 시리즈면 권 목록으로 진입, 단권이면 기존 동작 그대로
  - 기존 `book:selected` 이벤트 계약 `{id, title, cover}` 유지 (게임 화면이 의존)
- [ ] **`app/views/games/catalog/index.html.erb:7-27`** — 파셜 미사용 인라인이라 별도 반영
- [ ] **`Books::SearchService#normalize_naver`** (122-139행) — 원격 검색(🔍)도 같은 책 여러 판본을 반환할 수 있음.
      이번 범위에 포함할지 별건으로 뺄지 결정 필요

### 2. 테스트 작업 목록

- [ ] **기존 깨질 테스트 수정** — autocomplete JSON 키 집합 고정 테스트 (`test/` 하위, 41행 근처)
- [ ] 컨트롤러: 새 JSON 계약 (`series_count`, `volume` 등)
- [ ] 컨트롤러: 그룹핑 정확성 — 시리즈 26권이 1행으로 접히는지
- [ ] 컨트롤러: **단권 책이 2단계 없이 바로 선택되는지**
- [ ] rake: `volume` 백필 멱등성 (재실행해도 동일 결과, 기존 링크 보존)
- [ ] 통합: 독서활동(`mode: strict`) 화면에서 권 선택까지 e2e

### 3. 문서 갱신 (프로젝트 규칙)

`CLAUDE.md` 마트료시카 구조상, 변경한 폴더의 `CLAUDE.md`를 **반드시** 함께 갱신한다.

- [ ] `app/controllers/CLAUDE.md` — `books_controller.rb` 항목의 autocomplete JSON 계약 서술 수정
      (현재 `{id,title,author,cover_url,genre,classic}` 로 명시되어 있음)
- [ ] `db/CLAUDE.md` — books 스키마에 volume 추가 반영
- [ ] `lib/tasks/CLAUDE.md` — `books.rake` 의 volume 적재 반영
- [ ] `app/javascript/CLAUDE.md` — 자동완성 2단계 동작 반영
- [ ] `test/CLAUDE.md` — 신규 테스트 반영

### 4. 검증 방법

```bash
# 1. 마이그레이션 + 백필
bin/rails db:migrate
bin/rails books:seed_full
# → "Loaded 8503 rows" / total=8650 유지 확인 (행 수가 줄면 안 됨)

# 2. volume 백필 확인 (읽기 전용)
bin/rails runner 'puts Book.where("title LIKE ?", "%설민석의 삼국지 대모험%").order(:volume).pluck(:volume, :isbn).inspect'
# → [[1, "9791197226199"], [2, "9791191496024"], ... [26, ...]] 기대

# 3. 링크 보존 확인
bin/rails runner 'puts Report.where.not(book_id: nil).count'
# → 마이그레이션 전후 동일해야 함

# 4. 자동완성 응답 확인
curl -s 'http://localhost:3000/books/autocomplete?q=삼국지' -H 'Accept: application/json' | jq
# → 같은 title+author 가 1행으로 접히고 series_count 가 실려야 함

# 5. 테스트
bin/rails test
```

브라우저 확인: 로그인 → 독서활동 → "삼국지" 입력 →
드롭다운에 서로 다른 시리즈들이 각 1행씩 뜨는지 → 시리즈 항목 클릭 → 권 목록 →
특정 권 선택 시 hidden `book_id` 가 그 권의 id로 채워지는지.

---

## 참고 — 핵심 파일 빠른 링크

| 파일 | 역할 |
|---|---|
| `app/controllers/books_controller.rb:43-57` | `#autocomplete` — 이번 증상의 서버 경로 |
| `app/javascript/controllers/book_search_controller.js` | 자동완성 Stimulus (디바운스·렌더·선택) |
| `app/views/books/_autocomplete_field.html.erb` | 공용 자동완성 파셜 |
| `lib/tasks/books.rake:38-78` | TSV 적재 (volume 유실 지점) |
| `db/seeds/elementary_books.tsv` | 원본 8,503행 — `volume` 컬럼 보유 |
| `db/schema.rb:137-152` | books 테이블 (isbn unique + CHECK) |
| `app/services/books/search_service.rb` | 네이버 검색 (autocomplete와 별개 경로) |
| `app/services/books/deduplicator.rb` | ISBN 중복 병합 — **이번 건과 무관, 대상 0건** |
