# lib/tasks/ — rake 시드 태스크

'책갈피'의 초기 카탈로그·기준 데이터를 멱등 적재하는 rake 태스크 모음입니다. `db/seeds.rb` 가 이들을 `Rake::Task["..."].invoke` 로 호출하므로, 실제 시드 로직은 대부분 여기에 있습니다. 모든 태스크는 `find_or_initialize_by`/`find_or_create_by!` 기반이라 재실행해도 안전합니다. (`config/application.rb` 의 `autoload_lib(ignore: %w[assets tasks])` 로 오토로드 대상에서는 제외됨.)

## 파일

- `schools.rake` — 세 태스크. **`schools:seed`**(CSV가 없는 개발/테스트용 축소 17교, production no-op). **`schools:fetch`**(키 필요; NEIS 전 페이지 수집→전국 검증→정렬→임시파일 fsync/원자 rename으로 `db/seeds/schools.csv` 교체, 실패 시 기존 파일 보존). **`schools:seed_full`**(CSV 헤더·구조·17개 교육청·최소 5,000교 검증 후 1,000행 배치 upsert; 현 스냅샷 학교는 neis/active, 사라진 기존 NEIS 학교와 구 합성 17교는 삭제 대신 inactive, manual 학교는 보존). 오프라인·멱등이며 CSV 경로는 `ENV["SCHOOLS_CSV"]`, 소형 테스트 fixture는 `SCHOOLS_ALLOW_PARTIAL=1`로 주입한다.
- `books.rake` — 세 태스크. **`books:seed`**(TSV가 없는 체크아웃용 축소 큐레이션: 초등 1~2/3~4/5~6 권장도서 + 고전, `title`+`author` 멱등). **`books:seed_full`**(`db/seeds/elementary_books.tsv` 8,502행을 오프라인·멱등 적재; `isbn13` 우선, 없으면 `title`+`author`; searched 캐시는 제외; TSV 값이 있는 메타만 비파괴 갱신하고 summary 보존). TSV가 있으면 `db:seed`의 기본 경로이고 없으면 `books:seed`로 폴백하며, `ENV["BOOKS_TSV"]`로 테스트 파일 주입 가능. **`books:enrich`**는 seeds 밖 수동 네트워크 보강이다.
- `monsters.rake` — `monsters:seed`(전체 24라인 72폼)·`monsters:seed_phase2`(Phase 1 위에 Phase 2 12라인 36폼 추가)·**`monsters:backfill_unlocks`**(`User.student.find_each`로 기존 학생 전원의 몬스터 해금을 `MonsterUnlock#evaluate!`로 재평가 — unlock_condition 롤아웃 후 소급 지급용 배치, `(user_id, dex_no)` 유니크+미보유 가드로 재실행해도 멱등. 과거 게임 플레이는 `game_plays` 원장에 없어 게임 조건 라인은 신규 플레이부터 누적)·`monsters:install_assets`(YAML 매핑 검증 후 애니메이션 WebP 72개를 `app/assets/images/monsters`에 멱등 설치). 종 데이터 적재는 `MonsterSeeder`가 담당하며 소스는 `db/seeds/monsters.yml`(라인 단위 `unlock_condition`은 stage 1 폼에만 포함).
- `quizzes.rake` — `quizzes:seed`. 시드된 도서 1권(기본 "마당을 나온 암탉")에 대해 게시(published) 전역 퀴즈 1개를 만들어 quiz(mcq) 게임을 즉시 플레이 가능하게 함. 문항은 `Ai::QuizDraftService` 로 5개 생성. `title` 기준 멱등. **Phase 1 콘텐츠축 메타(#9-seed)**: 퀴즈에 origin=teacher·content_axis=mcq·band(전역이라 g56 폴백)·content_version=1, 문항에 question_type=mcq_single·source=manual 을 명시해 신규 컬럼과 함께 재현되게 함(`test/tasks/quizzes_seed_test.rb`).
- `badges.rake` — `badges:seed`(뱃지 13종) + `shop_items:seed`(먹이·진화의 돌·장식 상점 아이템). 각각 `key`/`name` 기준 멱등.
- `games.rake` — `games:warm`(Phase 3 §3.5, A5). 카탈로그(추천/고전) 도서를 대상으로 `Games::ContentProvider.warm!` 로 **band×content_axis 워밍 잡을 사전 큐잉**해 학생 첫 플레이의 콜드-첫-오프라인 노출(특히 matching/hint_reveal)을 줄인다. 예산·rate limit·스코프 플래그를 준수하고 무키면 아무것도 적재하지 않으며(오프라인만), dedup(이미 워밍 중/AI 게시됨)은 `GenerateGameContentJob` 이 자체 가드한다. 시드 아닌 운영 태스크(스케줄/도서 지정 시 수동 실행).

## 패턴·규칙

- **`db/seeds.rb` 와의 관계**: 학교는 `schools.csv` 존재 시 `schools:seed_full`(없으면 `schools:seed`), 도서는 `elementary_books.tsv` 존재 시 `books:seed_full`(없으면 `books:seed`)을 선택한다. 전체 순서는 학교 → superadmin/system/sample users → monsters/badges/shop_items → 도서 → quizzes → app_settings이며, `quizzes:seed`는 superadmin·도서 이후여야 한다.
- 새 시드 태스크는 반드시 멱등하게 작성하고, 필요 시 `db/seeds.rb` 의 invoke 순서에 등록할 것.

---
> ⚠️ **유지보수 규칙**: `.rake` 파일이 추가·삭제되거나 태스크명·적재 데이터가 바뀌면 이 CLAUDE.md와 `db/seeds.rb`(invoke 목록·순서), 그리고 관련 시드 소스(`db/seeds/monsters.yml`)를 함께 확인·갱신하세요.
