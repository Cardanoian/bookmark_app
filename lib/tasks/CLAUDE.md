# lib/tasks/ — rake 시드 태스크

'책갈피'의 초기 카탈로그·기준 데이터를 멱등 적재하는 rake 태스크 모음입니다. `db/seeds.rb` 가 이들을 `Rake::Task["..."].invoke` 로 호출하므로, 실제 시드 로직은 대부분 여기에 있습니다. 모든 태스크는 `find_or_initialize_by`/`find_or_create_by!` 기반이라 재실행해도 안전합니다. (`config/application.rb` 의 `autoload_lib(ignore: %w[assets tasks])` 로 오토로드 대상에서는 제외됨.)

## 파일

- `schools.rake` — 세 태스크. **`schools:seed`**(축소 17교, `neis_code` 기준 속성 동기화·멱등; 경북 대표교는 `포항원동초등학교`; **프로덕션에서는 no-op 환경가드** — 합성 코드 오염 방지). **`schools:fetch`**(dev 전용·키 필요, `Schools::NeisFetcher`로 NEIS 초등학교 전량 수집→`db/seeds/schools.csv` 생성; 네트워크). **`schools:seed_full`**(CSV→`School.upsert_all(unique_by: :neis_code, record_timestamps:)`, name 공백 필터·균일 컬럼셋; 오프라인·멱등). 획득(fetch)↔적재(seed_full) 분리로 시드는 무네트워크. CSV 경로는 `ENV["SCHOOLS_CSV"]`로 테스트 주입 가능.
- `books.rake` — 세 태스크. **`books:seed`**(밴드별 큐레이션 카탈로그: 초등 1~2/3~4/5~6 권장도서 + 고전, `grade_band`는 `Book::GRADE_BANDS` 표준 라벨; `title`+`author` 멱등). **`books:seed_full`**(`db/seeds/elementary_books.tsv` — `script/build_elementary_books_tsv.rb` 산출물, 8,502행 — 을 오프라인·멱등 적재. `isbn13` 우선, 없으면 `title`+`author`로 `find_or_initialize_by`; `SearchService`가 만든 `searched` 캐시 행은 스코프에서 제외해 덮어쓰지 않음; `publisher`/`cover_url`/`grade_band`/`genre`는 TSV 값이 있을 때만 대입해 비파괴 보존, `summary`는 건드리지 않음; TSV 경로는 `ENV["BOOKS_TSV"]`로 테스트 주입 가능. `schools:seed_full`과 같은 획득↔적재 분리 규약 — `db/seeds.rb`에는 편입하지 않고 `bin/rails books:seed_full`로 수동 실행). **`books:enrich`**(seeds.rb 밖·수동·네트워크; `Books::CatalogEnricher`로 표지/ISBN/출판사를 네이버로 사후 보강, 큐레이션 행만 제자리 갱신·무키 시 no-op). 소스는 학교도서관저널 추천도서목록 기반 큐레이션(`books:seed`) + 정보나루/NLCY/앱 큐레이션 병합(`books:seed_full`, `script/CLAUDE.md`).
- `monsters.rake` — `monsters:seed`(전체 24라인 72폼)·`monsters:seed_phase2`(Phase 1 위에 Phase 2 12라인 36폼 추가)·**`monsters:backfill_unlocks`**(`User.student.find_each`로 기존 학생 전원의 몬스터 해금을 `MonsterUnlock#evaluate!`로 재평가 — unlock_condition 롤아웃 후 소급 지급용 배치, `(user_id, dex_no)` 유니크+미보유 가드로 재실행해도 멱등. 과거 게임 플레이는 `game_plays` 원장에 없어 게임 조건 라인은 신규 플레이부터 누적)·`monsters:install_assets`(YAML 매핑 검증 후 애니메이션 WebP 72개를 `app/assets/images/monsters`에 멱등 설치). 종 데이터 적재는 `MonsterSeeder`가 담당하며 소스는 `db/seeds/monsters.yml`(라인 단위 `unlock_condition`은 stage 1 폼에만 포함).
- `quizzes.rake` — `quizzes:seed`. 시드된 도서 1권(기본 "마당을 나온 암탉")에 대해 게시(published) 전역 퀴즈 1개를 만들어 quiz(mcq) 게임을 즉시 플레이 가능하게 함. 문항은 `Ai::QuizDraftService` 로 5개 생성. `title` 기준 멱등. **Phase 1 콘텐츠축 메타(#9-seed)**: 퀴즈에 origin=teacher·content_axis=mcq·band(전역이라 g56 폴백)·content_version=1, 문항에 question_type=mcq_single·source=manual 을 명시해 신규 컬럼과 함께 재현되게 함(`test/tasks/quizzes_seed_test.rb`).
- `badges.rake` — `badges:seed`(뱃지 13종) + `shop_items:seed`(먹이·진화의 돌·장식 상점 아이템). 각각 `key`/`name` 기준 멱등.
- `games.rake` — `games:warm`(Phase 3 §3.5, A5). 카탈로그(추천/고전) 도서를 대상으로 `Games::ContentProvider.warm!` 로 **band×content_axis 워밍 잡을 사전 큐잉**해 학생 첫 플레이의 콜드-첫-오프라인 노출(특히 matching/hint_reveal)을 줄인다. 예산·rate limit·스코프 플래그를 준수하고 무키면 아무것도 적재하지 않으며(오프라인만), dedup(이미 워밍 중/AI 게시됨)은 `GenerateGameContentJob` 이 자체 가드한다. 시드 아닌 운영 태스크(스케줄/도서 지정 시 수동 실행).

## 패턴·규칙

- **`db/seeds.rb` 와의 관계**: `seeds.rb` 가 `schools:seed → monsters:seed → badges:seed → shop_items:seed → books:seed → quizzes:seed` 순으로 invoke. `quizzes:seed` 는 superadmin·도서에 의존하므로 books/superadmin 이후에 와야 함(순서 의미 있음).
- 새 시드 태스크는 반드시 멱등하게 작성하고, 필요 시 `db/seeds.rb` 의 invoke 순서에 등록할 것.

---
> ⚠️ **유지보수 규칙**: `.rake` 파일이 추가·삭제되거나 태스크명·적재 데이터가 바뀌면 이 CLAUDE.md와 `db/seeds.rb`(invoke 목록·순서), 그리고 관련 시드 소스(`db/seeds/monsters.yml`)를 함께 확인·갱신하세요.
