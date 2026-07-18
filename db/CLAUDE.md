# db/ — 데이터베이스 스키마·마이그레이션·시드

'책갈피'의 SQLite 데이터베이스 정의를 담은 폴더입니다. 운영(production)은 primary·cache·queue·cable **4개 DB**를 쓰며, 각 보조 DB는 Solid Cache/Queue/Cable 전용 스키마를 따로 가집니다. 애플리케이션 도메인 테이블은 primary(`schema.rb`)에 모두 정의됩니다.

## 파일

- `schema.rb` — primary DB 현재 스키마(auto-generated, 33개 테이블, version `2026_07_18_000002`). **직접 편집 금지** — 반드시 마이그레이션을 추가/실행해 재생성할 것. `bin/rails db:schema:load` 의 기준.
- `seeds.rb` — 시드 오케스트레이션. `db/seed` 진입점으로, 아래 rake 태스크들을 순서대로 `invoke` 하고 그 사이에 superadmin(총괄관리자)·**system 유저(온디맨드 캐시 소유자, origin=system Quiz 의 created_by)**·**역할별 개발 샘플 계정**·`app_settings` 기본 플래그를 멱등 생성. (rake 상세는 `lib/tasks/CLAUDE.md`) 샘플 퀴즈는 `quizzes:seed` 가 Phase 1 콘텐츠축 컬럼(origin=teacher/content_axis=mcq/band 유도/content_version=1, 문항 mcq_single·manual)까지 채워 재현되므로 시드가 Phase 1 스키마와 함께 깨끗이 재적재된다(#9-seed).
  - 순서: `schools:seed` → superadmin → **system 유저** → **역할 샘플 계정** → `monsters:seed`·`badges:seed`·`shop_items:seed` → `books:seed` → `quizzes:seed` → `app_settings`. **`monsters:seed`는 라인 단위 `unlock_condition`(자동 해금 규칙)도 stage 1 폼에 함께 적재**하지만 invoke 순서 자체는 바뀌지 않는다.
  - **superadmin(총괄관리자)은 credentials(`:superadmin` → `name`·`email`·`password`)를 단일 진실로 읽어 매 시드마다 이름·이메일·비번을 동기화**(리포에 비번 하드코딩 금지). credentials 미설정 시 폴백(`총괄관리자`/`admin@example.com`/`changeme1234`). **총괄관리자도 교직원이라 이메일로 로그인**(sessions#staff_create)하므로 이메일을 부여한다. 이름을 바꾸면 이전 이름 계정은 별도로 남는다.
  - **역할 샘플 계정**: **로그인 표면이 2분화**되어(sessions_controller) 학생은 튜플(학교·학급·이름)로, 교직원은 **이메일**로 로그인한다. superadmin(credentials) 외 학생·담임교사·교무관리자·사서 4종은 **모두 같은 학교(`포항원동초등학교`, neis_code `7150001`)** 소속으로 seeds.rb 에 하드코딩(김담임=교사 3학년1반 담임 `teacher@example.com` / 이학생=학생 3학년1반, **이메일 없음** / 박교무=교무관리자 `schooladmin@example.com` / 최사서=사서 `librarian@example.com`). 대상 학교는 `schools:seed` 선적재가 전제(없으면 스킵). 비번은 `<role>1234`. 헬퍼 `seed_user` 는 신규 생성뿐 아니라 **기존 계정의 비어 있는 attrs(예: email 컬럼 신설 후)만 백필**하므로 `db:reset` 없이 재시드만으로 교직원 이메일 로그인이 가능해진다(비번은 미변경).
  - system 유저는 superadmin 과 같은 신원 규약(name + school_id:nil + classroom_id:nil)으로 `find_or_initialize_by` 멱등 생성(로그인 불가한 시스템 액터). `ContentProvider.system_user`도 같은 신원으로 멱등 확보한다.
  - 기본 `feature_flags` 에 `on_demand_games => true`(온디맨드 게임 워밍 전역 kill switch, Phase 2b C3) 포함. 스코프 오버라이드 규약은 `config/CLAUDE.md`·`app_setting.rb` 참조.
- `cable_schema.rb` — Solid Cable 보조 DB(`solid_cable_messages`). production `cable` DB.
- `cache_schema.rb` — Solid Cache 보조 DB(`solid_cache_entries`). production `cache` DB.
- `queue_schema.rb` — Solid Queue 보조 DB(잡·실행·세마포어 등 다수 테이블). production `queue` DB.

## 하위 폴더 (별도 CLAUDE.md 불필요)

### migrate/ — 마이그레이션 (타임스탬프 순으로 도메인 그룹 적재)

primary DB 스키마를 시간순으로 쌓아 올립니다. 대략 다음 도메인 순서로 테이블이 생성됩니다.

1. **학교·사용자·학급** (`20260706000001`–`000004`): `schools` → `users` → `classrooms` → users 에 classroom FK.
2. **도서·독후감** (`20260706000005`–`000006`, `133035`): `books` → `reports`(level·reviewed 등 인덱스) → Active Storage 테이블(사진 첨부).
3. **몬스터·게이미피케이션** (`20260706140001`–`140011`): `monster_species` → `user_monsters` → users 에 active_monster FK → `shop_items` → `purchases` → `badges` → `user_badges` → `missions` → `challenges` → `seasons` → reports 에 challenge·mission FK.
4. **커뮤니티·퀴즈·도서관** (`20260707000001`–`000010`): `board_posts` → `cheers` → `stickers` → `topics` → `forum_posts` → `quizzes` → `quiz_questions` → `quiz_attempts` → `library_loans` → `library_events`.
5. **설정·보정** (`20260707000011`–`000017`): `app_settings` 생성, reports/quiz_attempts 에 `points_awarded`, users 에 `approved`(교사 가입 승인 게이트 — 이후 `20260715000001` 에서 제거), 누락 FK 일괄 추가, topics `forum_posts_count` 카운터 캐시, 랭킹용 복합 인덱스.
6. **게임 온디맨드 콘텐츠축(Phase 1~2b)** (`20260712000001`–`000004`): `quiz_questions` 에 `question_type`·`content`·`answer`·`explanation`·`difficulty`·`source` → `quizzes` 에 `content_axis`·`band`·`origin`·`generation_status`·`content_version`·`reported` + 콘텐츠축 델타 상한 지원 인덱스(`index_quizzes_on_content_axis_delta`) → 기존 데이터 백필(origin=teacher/content_axis=mcq/band 유도, mcq_single/manual; `up`/`down` 왕복 무손실) → **dedup 부분 유니크 인덱스(`index_quizzes_on_content_axis_dedup`, Phase 2b §2b.4/A2)**: `(book_id, band, content_axis, content_version)` **UNIQUE WHERE origin = 1**(정수 술어 = `Quiz.origins[:system]`; 문자열 `'system'` 금지 — 정수 컬럼과 0행 매칭 시 dedup 무효). teacher 행(origin=0)은 술어 제외로 중복 허용. `insert rescue RecordNotUnique` thundering-herd → 콘텐츠축당 1생성.
7. **FK on_delete 정합화(Phase 6)** (`20260712000005`–`000006`): 모델 nullify 의도와 어긋난 두 FK 의 `on_delete` 를 맞춘다. `reports.book_id → books`(#6)·`monster_species.evolves_from_id → monster_species` 자기참조(#8)에 **`on_delete: :nullify`** 부여 — 부모 삭제 시 자식을 남기고 참조만 끊는다(모델 `Book#has_many :reports, dependent: :nullify`·`MonsterSpecies#has_many :next_forms, dependent: :nullify` 와 정합). SQLite 는 FK 변경을 **테이블 재빌드**로 처리하므로 `up`/`down` 모두 재빌드·데이터 복사 → **왕복 무손실**(`test/models/fk_on_delete_roundtrip_test.rb` 로 검증). 컬럼 추가/삭제 없음 → 테이블 수 불변.
8. **게임 다양성 축소 + 책 소개 대결(book)** (`20260712000007`–`000009`): `quiz_attempts` 에 `hint_reveals`(whoami 서버 힌트수) 추가 후, 독서게임을 교육 다양성 우선 5종으로 줄이며 소셜 게임 `book`(책 소개 대결)을 신설. `book_intros`(user·book·classroom FK + body + votes_count, 인덱스 `[book_id, classroom_id]`) → `book_intro_votes`(book_intro·user FK, **`(book_intro_id, user_id)` UNIQUE**=소개당 1인 1표, votes_count counter_cache). 퀴즈 파이프라인 밖(Gemini/Quiz 미생성). **+2 테이블(28→30)**. 축소로 제거된 게임 표면·콘텐츠축은 코드/enum 매핑 축소일 뿐이라 마이그레이션 불요(정수 컬럼 그대로).
9. **무게이트 롤아웃 콘텐츠 신고** (`20260712000010`): `quizzes` 에 `reports_count`(counter_cache) 추가 + `quiz_reports`(quiz·user FK, **`(quiz_id, user_id)` UNIQUE**=1인 1신고, cheer/vote 패턴). 서로 다른 `REPORT_HIDE_THRESHOLD`(2)명 신고 시 자동 숨김+재생성, 신고자 학급 담임 대시보드로 사후 검토. **+1 테이블(30→31)**.
10. **학교 도로명주소 컬럼** (`20260713000001`): `schools` 에 NEIS 도로명주소(`ORG_RDNMA`) 원본 저장용 `address` 컬럼 추가(gu 파싱 검증·향후 학교 검색 UX 용). 컬럼 추가만이라 테이블 수 불변(31 유지). 기존 축소 시드 17교는 `address` nil 로 남는다.
11. **게시판 글 좋아요** (`20260713000002`): `forum_post_likes`(forum_post·user FK, `(forum_post_id, user_id)` UNIQUE=1인 1좋아요, `forum_posts.likes_count` counter_cache). **+1 테이블(31→32)**.
12. **로그인 표면 2분화(교직원 이메일 로그인)** (`20260714000001`): `users` 에 `email`(nullable) + **UNIQUE 인덱스** 추가. 학생은 튜플(학교·학급·이름) 로그인이라 email=NULL(SQLite 유니크 인덱스는 NULL 다중 허용), 교직원(교사·관리자·사서·총괄)은 이메일로 로그인한다(sessions#staff_create). 저장 전 소문자 정규화(user.rb `normalize_email`)라 대소문자 무관 유일성이 인덱스만으로 보장. 컬럼 추가만이라 테이블 수 불변(32 유지).
13. **교사 가입 승인 게이트 제거** (`20260715000001`): `users` 에서 `approved` 컬럼 제거. 교사는 회원가입 즉시 로그인·활동할 수 있게 되어(승인 대기 폐지) 관련 세션 게이트(application_controller)·로그인 게이트(sessions_controller)·관리자 승인 UI(admin/users 의 `approve`/`unapprove`)가 함께 사라졌다. `down` 은 컬럼을 되살리고 기존 사용자를 모두 승인(true) 처리한다. 컬럼 삭제만이라 테이블 수 불변(32 유지).
14. **몬스터 라인 해금 조건 컬럼** (`20260716000001`): `monster_species` 에 `unlock_condition`(JSON, nullable) 컬럼 추가. 라인 단위 자동 해금 규칙(`evolve_condition`과 같은 조건 해시 문법·화이트리스트를 공유하되 별도 컬럼)을 stage 1 폼에만 저장하고, stage 2·3·아직 규칙이 없는 라인은 NULL. 컬럼 추가만이라 테이블 수 불변(32 유지).
15. **게임 완료 원장(game_plays)** (`20260716000002`): `game_plays`(user FK·`game_type`·book FK nullable·`played_on`) 신설. 몬스터 해금 지표(`game_plays`/`distinct_games`/`game_books`, `ReadingStats`)의 서버 권위 소스. 같은 학생·게임·(책)·일자 재제출을 막기 위한 **부분 유니크 인덱스 2개**: book 있는 플레이는 `(user_id, game_type, book_id, played_on)` UNIQUE WHERE `book_id IS NOT NULL`, book 없는 플레이는 `(user_id, game_type, played_on)` UNIQUE WHERE `book_id IS NULL`(SQLite 유니크 인덱스가 NULL 을 서로 구별해 단일 인덱스로는 book-less 재제출을 dedup 할 수 없기 때문 — 선례: `index_quizzes_on_content_axis_dedup` 부분 유니크). **+1 테이블(32→33)**.
16. **도서 장르 컬럼** (`20260718000001`): `books` 에 `genre`(string, nullable) 추가 — 10개 장르. 네이버 검색으로 새로 등록되는 도서는 비동기 `BookEnrichmentJob`(무API `Books::GenreInference`)이 공란 genre 를 채운다(고전은 여전히 `category` enum 의 classic). 컬럼 추가만이라 테이블 수 불변(33 유지).
17. **몬스터 발견 연출 마킹 컬럼** (`20260718000002`): `user_monsters` 에 `celebrated_at`(datetime, nullable — NULL=미연출) + **부분 인덱스**(`index_user_monsters_pending_discovery`, `WHERE celebrated_at IS NULL`) 추가 — 발견 연출 영속 드레인(`pending_celebration` scope)용. 마이그레이션이 기존 보유분을 백필(확인 처리=현재시각 마킹)해 **신규 발견만** 드레인 큐에 뜨게 한다. 컬럼 추가만이라 테이블 수 불변(33 유지). `schema.rb` version 은 `2026_07_18_000002`.

### seeds/ — 시드 데이터

- `monsters.yml` — 반려 몬스터 도감 데이터(`docs/monsters.md §7` YAML 을 verbatim 반영). **24라인 × 3스테이지 = 72폼**. 6속성(story·knowledge·nature·emotion·adventure·imagination) 각 4라인, Phase 1(12라인)·Phase 2(12라인)로 구분. 라인당 `forms` 3개(stage 1·2·3), `evolve_condition` 은 다음 단계 승급 조건. **라인 단위 `unlock_condition`**(자동 해금 규칙, `docs/monster_unlocks.md §5`)은 스타터 이후 발견 조건이며 시더가 stage 1 폼에만 대입(2·3단계는 nil로 두어 재시드해도 조건이 새지 않게 함). `monsters:seed`(via `MonsterSeeder`)가 소비.
- `schools.csv` — 전량 학교 시드 계약. 헤더 `neis_code,name,region,gu,office_code,address`. `schools:fetch`(NEIS, `Schools::NeisFetcher`)가 생성하고 `schools:seed_full`이 `upsert_all`로 소비. 리포에 없으면 `seed_full`은 no-op(축소 17교 시드 유지) — **파일 자체는 커밋되지 않을 수 있다**.
- `elementary_books.tsv` — 초등 전학년 도서 카탈로그(`script/build_elementary_books_tsv.rb`의 산출물, 8,502행, 탭 구분; 정보나루 학년별 인기대출 API + NLCY 사서 추천 목록 + 앱 큐레이션 `Book` 레코드를 병합). `books:seed_full`(`lib/tasks/CLAUDE.md`)이 `isbn13` 우선(없으면 `title`+`author`)으로 오프라인·멱등 적재한다. TSV 컬럼 중 `books` 스키마에 없는 것(rank·loans·kdc·monster_element·topic_tags 등)은 드롭되고, `publisher`/`cover_url`/`grade_band`는 값이 있을 때만 대입해 기존값을 비파괴 보존하며 `summary`는 건드리지 않는다. `schools.csv`와 달리 git 커밋 대상(구 `docs/elementary_books.tsv`에서 이동).

## 패턴·규칙

- 스키마 변경은 **마이그레이션으로만**. `schema.rb`·보조 `*_schema.rb` 직접 편집 금지.
- 모든 시드는 **멱등**(`find_or_initialize_by`/`find_or_create_by!`)이어야 재실행 안전. 새 시드 추가 시 이 규칙 준수.
- 보조 DB(cache/queue/cable) 마이그레이션 경로는 `database.yml` 에 `db/cache_migrate` 등으로 분리 지정됨(`config/CLAUDE.md` 참조).

---
> ⚠️ **유지보수 규칙**: 마이그레이션이 추가되면 위 도메인 그룹 요약과 `schema.rb` 테이블 수를 갱신하세요. 시드 파일(`monsters.yml`)이나 `seeds.rb` invoke 순서가 바뀌면 이 문서와 `lib/tasks/CLAUDE.md` 를 함께 확인하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
