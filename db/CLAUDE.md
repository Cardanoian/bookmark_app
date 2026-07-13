# db/ — 데이터베이스 스키마·마이그레이션·시드

'책갈피'의 SQLite 데이터베이스 정의를 담은 폴더입니다. 운영(production)은 primary·cache·queue·cable **4개 DB**를 쓰며, 각 보조 DB는 Solid Cache/Queue/Cable 전용 스키마를 따로 가집니다. 애플리케이션 도메인 테이블은 primary(`schema.rb`)에 모두 정의됩니다.

## 파일

- `schema.rb` — primary DB 현재 스키마(auto-generated, 32개 테이블, version `2026_07_13_000002`). **직접 편집 금지** — 반드시 마이그레이션을 추가/실행해 재생성할 것. `bin/rails db:schema:load` 의 기준.
- `seeds.rb` — 시드 오케스트레이션. `db/seed` 진입점으로, 아래 rake 태스크들을 순서대로 `invoke` 하고 그 사이에 superadmin(총괄관리자)·**system 유저(온디맨드 캐시 소유자, origin=system Quiz 의 created_by)**·`app_settings` 기본 플래그를 멱등 생성. (rake 상세는 `lib/tasks/CLAUDE.md`) 샘플 퀴즈는 `quizzes:seed` 가 Phase 1 콘텐츠축 컬럼(origin=teacher/content_axis=mcq/band 유도/content_version=1, 문항 mcq_single·manual)까지 채워 재현되므로 시드가 Phase 1 스키마와 함께 깨끗이 재적재된다(#9-seed).
  - 순서: `schools:seed` → superadmin → **system 유저** → `monsters:seed`·`badges:seed`·`shop_items:seed` → `books:seed` → `quizzes:seed` → `app_settings`.
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
5. **설정·보정** (`20260707000011`–`000017`): `app_settings` 생성, reports/quiz_attempts 에 `points_awarded`, users 에 `approved`, 누락 FK 일괄 추가, topics `forum_posts_count` 카운터 캐시, 랭킹용 복합 인덱스.
6. **게임 온디맨드 콘텐츠축(Phase 1~2b)** (`20260712000001`–`000004`): `quiz_questions` 에 `question_type`·`content`·`answer`·`explanation`·`difficulty`·`source` → `quizzes` 에 `content_axis`·`band`·`origin`·`generation_status`·`content_version`·`reported` + 콘텐츠축 델타 상한 지원 인덱스(`index_quizzes_on_content_axis_delta`) → 기존 데이터 백필(origin=teacher/content_axis=mcq/band 유도, mcq_single/manual; `up`/`down` 왕복 무손실) → **dedup 부분 유니크 인덱스(`index_quizzes_on_content_axis_dedup`, Phase 2b §2b.4/A2)**: `(book_id, band, content_axis, content_version)` **UNIQUE WHERE origin = 1**(정수 술어 = `Quiz.origins[:system]`; 문자열 `'system'` 금지 — 정수 컬럼과 0행 매칭 시 dedup 무효). teacher 행(origin=0)은 술어 제외로 중복 허용. `insert rescue RecordNotUnique` thundering-herd → 콘텐츠축당 1생성.
7. **FK on_delete 정합화(Phase 6)** (`20260712000005`–`000006`): 모델 nullify 의도와 어긋난 두 FK 의 `on_delete` 를 맞춘다. `reports.book_id → books`(#6)·`monster_species.evolves_from_id → monster_species` 자기참조(#8)에 **`on_delete: :nullify`** 부여 — 부모 삭제 시 자식을 남기고 참조만 끊는다(모델 `Book#has_many :reports, dependent: :nullify`·`MonsterSpecies#has_many :next_forms, dependent: :nullify` 와 정합). SQLite 는 FK 변경을 **테이블 재빌드**로 처리하므로 `up`/`down` 모두 재빌드·데이터 복사 → **왕복 무손실**(`test/models/fk_on_delete_roundtrip_test.rb` 로 검증). 컬럼 추가/삭제 없음 → 테이블 수 불변.
8. **게임 다양성 축소 + 책 소개 대결(book)** (`20260712000007`–`000009`): `quiz_attempts` 에 `hint_reveals`(whoami 서버 힌트수) 추가 후, 독서게임을 교육 다양성 우선 5종으로 줄이며 소셜 게임 `book`(책 소개 대결)을 신설. `book_intros`(user·book·classroom FK + body + votes_count, 인덱스 `[book_id, classroom_id]`) → `book_intro_votes`(book_intro·user FK, **`(book_intro_id, user_id)` UNIQUE**=소개당 1인 1표, votes_count counter_cache). 퀴즈 파이프라인 밖(Gemini/Quiz 미생성). **+2 테이블(28→30)**. 축소로 제거된 게임 표면·콘텐츠축은 코드/enum 매핑 축소일 뿐이라 마이그레이션 불요(정수 컬럼 그대로).
9. **무게이트 롤아웃 콘텐츠 신고** (`20260712000010`): `quizzes` 에 `reports_count`(counter_cache) 추가 + `quiz_reports`(quiz·user FK, **`(quiz_id, user_id)` UNIQUE**=1인 1신고, cheer/vote 패턴). 서로 다른 `REPORT_HIDE_THRESHOLD`(2)명 신고 시 자동 숨김+재생성, 신고자 학급 담임 대시보드로 사후 검토. **+1 테이블(30→31)**.
10. **학교 도로명주소 컬럼** (`20260713000001`): `schools` 에 NEIS 도로명주소(`ORG_RDNMA`) 원본 저장용 `address` 컬럼 추가(gu 파싱 검증·향후 학교 검색 UX 용). 컬럼 추가만이라 테이블 수 불변(31 유지). 기존 축소 시드 17교는 `address` nil 로 남는다.
11. **게시판 글 좋아요** (`20260713000002`): `forum_post_likes`(forum_post·user FK, `(forum_post_id, user_id)` UNIQUE=1인 1좋아요, `forum_posts.likes_count` counter_cache). **+1 테이블(31→32)**, `schema.rb` version 은 `2026_07_13_000002`.

### seeds/ — 시드 데이터

- `monsters.yml` — 반려 몬스터 도감 데이터(`docs/monsters.md §7` YAML 을 verbatim 반영). **24라인 × 3스테이지 = 72폼**. 6속성(story·knowledge·nature·emotion·adventure·imagination) 각 4라인, Phase 1(12라인)·Phase 2(12라인)로 구분. 라인당 `forms` 3개(stage 1·2·3), `evolve_condition` 은 다음 단계 승급 조건. `monsters:seed`(via `MonsterSeeder`)가 소비.
- `schools.csv` — 전량 학교 시드 계약. 헤더 `neis_code,name,region,gu,office_code,address`. `schools:fetch`(NEIS, `Schools::NeisFetcher`)가 생성하고 `schools:seed_full`이 `upsert_all`로 소비. 리포에 없으면 `seed_full`은 no-op(축소 17교 시드 유지) — **파일 자체는 커밋되지 않을 수 있다**.

## 패턴·규칙

- 스키마 변경은 **마이그레이션으로만**. `schema.rb`·보조 `*_schema.rb` 직접 편집 금지.
- 모든 시드는 **멱등**(`find_or_initialize_by`/`find_or_create_by!`)이어야 재실행 안전. 새 시드 추가 시 이 규칙 준수.
- 보조 DB(cache/queue/cable) 마이그레이션 경로는 `database.yml` 에 `db/cache_migrate` 등으로 분리 지정됨(`config/CLAUDE.md` 참조).

---
> ⚠️ **유지보수 규칙**: 마이그레이션이 추가되면 위 도메인 그룹 요약과 `schema.rb` 테이블 수를 갱신하세요. 시드 파일(`monsters.yml`)이나 `seeds.rb` invoke 순서가 바뀌면 이 문서와 `lib/tasks/CLAUDE.md` 를 함께 확인하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
