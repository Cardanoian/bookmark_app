# app/services — 도메인 로직 서비스 객체 계층

컨트롤러를 얇게 유지하기 위해 몬스터·랭킹·독서지표·외부 API 연동 같은 도메인 로직을 담는 PORO 서비스 계층. 대부분 `initialize(user)` 로 주체를 받아 `call`/도메인 메서드를 노출한다. 외부 연동(AI·도서검색·인기대출)은 키가 없거나 실패해도 규칙기반/로컬/빈 결과로 폴백해 절대 크래시하지 않는 것이 공통 계약이다.

## 파일
- `monster_acquisition.rb` — 노력 기반 몬스터 획득(스타터 3종 선택 + 마일스톤 발견). 가챠·랜덤 경로 없음, 라인 미보유 시에만 stage 1 폼 생성.
- `monster_seeder.rb` — 도감 시드(`db/seeds/monsters.yml` → `monster_species`). 24라인×3=72폼 전량/Phase별 적재, `evolves_from` 자동 연결, key 기준 멱등.
- `ranking_board.rb` — 랭킹 집계(학급/포디움/학교/전국/챌린지/명예의 전당). 부작용 없는 순수 조회, 그룹 집계로 N+1 제거.
- `reading_stats.rb` — 진화·뱃지 조건 판정용 독서 지표 집계(포인트·독후감·스트릭 등). `meets?(condition)` 로 조건 해시를 AND 판정, 지표는 메모이즈.
- `rate_limiter.rb` — **Solid Cache 원자 increment 기반 rate limit / 예산 유틸(Phase 2b §2b.5)**. `allow?(key, limit:, period:)`·`warming_allowed?(user_id)`(per-user 시간당 한도 AND 글로벌 일일 예산). 온디맨드 게임 워밍 방어에 쓰이며, Phase 6 #7(로그인 스로틀)이 같은 프리미티브를 재사용하도록 설계. 초과 시 호출자는 오프라인 강등/차단으로 우아하게 대응. 저장소 주입 가능(기본 `Rails.cache`; test 는 null_store 라 카운팅 스토어 주입).

## 하위 폴더
- [`ai/`](ai/CLAUDE.md) — Google Gemini 연동 AI 서비스(5축 첨삭·OCR·퀴즈생성·진위확인)와 규칙기반 폴백.
- [`games/`](games/CLAUDE.md) — 독서게임 서버 권위 채점(`question_scorer` 4종)·멱등 델타 적립(`point_award` origin 분기)·플레이 기록(`quiz_play`)·**콘텐츠축 캐시-우선 리졸버(`content_provider`, Phase 2b)**.

## 소규모 하위 폴더 (별도 CLAUDE.md 없음)
- `books/` — 도서 검색·보강 2파일. `search_service.rb`(네이버 도서 API 조회·정규화 후 `books` 캐시 upsert(`category: searched`), 무키/실패 시 로컬 `books`(title LIKE) 폴백. **무한 증가 방어(#2)**: searched 행은 `BooksController#index` 카탈로그에서 제외(1차 방어)되고 로컬 검색 폴백에서만 쓰인다. 물리 TTL 정리는 독후감 참조(`reports.book_id`) 때문에 미참조 오래된 행만 비우는 후속 작업으로 다룬다(`cache` 주석 참고). **`#query`**[캐시 부작용 없는 순수 조회 — enrich 용으로 추가] 병행) + `catalog_enricher.rb`(큐레이션 도서(recommended·classic) 표지/ISBN/출판사를 네이버로 제자리 보강. `SearchService#query` 를 써서 별도 `:searched` 행을 만들지 않고, 보강 후 선존 동일 isbn `searched` 행은 reconcile 삭제. service·throttle DI, 무키 시 no-op).
- `library/data4library_service.rb` — 정보나루(data4library.kr) 인기대출 OpenAPI 래퍼. 무키/실패 시 `[]` 반환(호출자는 CSV 업로드 폴백), 실패 사유는 `last_error` 로 노출.
- `schools/` — NEIS 학교기본정보 연동 2파일. `gu_parser.rb`(NEIS 도로명주소 `ORG_RDNMA` → 시군구(gu) 추출 순수 PORO. 첫 시/군/구 토큰=기초자치단체, 도농복합시는 시 반환, 세종 등 단층제[`SINGLE_TIER_SIDO` 예외표]는 nil) + `neis_fetcher.rb`(NEIS 학교기본정보 OpenAPI `schoolInfo` 래퍼. 초등학교만 필터·페이지네이션·gu 파싱, connection DI, 무키/실패 시 `[]`). 파싱 로직을 dev 전용 rake(`schools:fetch`)에서 분리해 단위 테스트 가능.

## 패턴·규칙
- **`available?` / graceful 폴백**: 외부 연동 서비스(`ai/*`·`books`·`library`)는 클래스 메서드 `self.available?`(내부 `configured?`/`available?`)로 **키 존재 여부만** 판단하며 네트워크를 호출하지 않는다. 키가 없거나 원격이 실패하면 규칙기반 첨삭·로컬 캐시·빈 배열 등으로 폴백한다.
- **Faraday 연결 주입**: 외부 HTTP는 Faraday로 하며, `initialize` 에 `connection:`/`*_connection:` 인자를 두어 테스트에서 스텁 연결을 주입(네트워크 차단)한다. 자격증명은 `Rails.application.credentials.dig(...)`.
- **멱등 포인트 델타**: 재제출/재첨삭 파밍을 막기 위해 이미 지급한 최고 적립액 대비 초과분(delta)만 `User#award_points` 로 적립한다(`games/point_award.rb`·`app/jobs/ai_review_job.rb` 공통 패턴). 게임은 상한을 `quiz.origin`으로 분기한다(teacher=per-quiz, system=콘텐츠축; `games/CLAUDE.md`).

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
