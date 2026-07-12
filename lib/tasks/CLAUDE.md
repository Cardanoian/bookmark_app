# lib/tasks/ — rake 시드 태스크

'책갈피'의 초기 카탈로그·기준 데이터를 멱등 적재하는 rake 태스크 모음입니다. `db/seeds.rb` 가 이들을 `Rake::Task["..."].invoke` 로 호출하므로, 실제 시드 로직은 대부분 여기에 있습니다. 모든 태스크는 `find_or_initialize_by`/`find_or_create_by!` 기반이라 재실행해도 안전합니다. (`config/application.rb` 의 `autoload_lib(ignore: %w[assets tasks])` 로 오토로드 대상에서는 제외됨.)

## 파일

- `schools.rake` — `schools:seed`. 17개 시도교육청별 대표 초등학교 1곳씩 적재(`neis_code` 기준 멱등). 원본 전체 학교 데이터(6,331곳)는 리포에 없어 축소 개발용 세트.
- `books.rake` — `books:seed`. 권장도서(`:recommended`) 24권 + 고전(`:classic`) 10권 = 대표 도서 카탈로그(`grade_band "초등 5~6"`). `title`+`author` 기준 멱등.
- `monsters.rake` — `monsters:seed`(전체 24라인 72폼)·`monsters:seed_phase2`(Phase 1 위에 Phase 2 12라인 36폼 추가). 실제 적재는 `MonsterSeeder`(테스트와 공유), 이 파일은 CLI 진입점만. 소스는 `db/seeds/monsters.yml`.
- `quizzes.rake` — `quizzes:seed`. 시드된 도서 1권(기본 "마당을 나온 암탉")에 대해 게시(published) 전역 퀴즈 1개를 만들어 quiz(mcq) 게임을 즉시 플레이 가능하게 함. 문항은 `Ai::QuizDraftService` 로 5개 생성. `title` 기준 멱등. **Phase 1 콘텐츠축 메타(#9-seed)**: 퀴즈에 origin=teacher·content_axis=mcq·band(전역이라 g56 폴백)·content_version=1, 문항에 question_type=mcq_single·source=manual 을 명시해 신규 컬럼과 함께 재현되게 함(`test/tasks/quizzes_seed_test.rb`).
- `badges.rake` — `badges:seed`(뱃지 13종) + `shop_items:seed`(먹이·진화의 돌·장식 상점 아이템). 각각 `key`/`name` 기준 멱등.
- `games.rake` — `games:warm`(Phase 3 §3.5, A5). 카탈로그(추천/고전) 도서를 대상으로 `Games::ContentProvider.warm!` 로 **band×content_axis 워밍 잡을 사전 큐잉**해 학생 첫 플레이의 콜드-첫-오프라인 노출(특히 matching/hint_reveal)을 줄인다. 예산·rate limit·스코프 플래그를 준수하고 무키면 아무것도 적재하지 않으며(오프라인만), dedup(이미 워밍 중/AI 게시됨)은 `GenerateGameContentJob` 이 자체 가드한다. 시드 아닌 운영 태스크(스케줄/도서 지정 시 수동 실행).

## 패턴·규칙

- **`db/seeds.rb` 와의 관계**: `seeds.rb` 가 `schools:seed → monsters:seed → badges:seed → shop_items:seed → books:seed → quizzes:seed` 순으로 invoke. `quizzes:seed` 는 superadmin·도서에 의존하므로 books/superadmin 이후에 와야 함(순서 의미 있음).
- 새 시드 태스크는 반드시 멱등하게 작성하고, 필요 시 `db/seeds.rb` 의 invoke 순서에 등록할 것.

---
> ⚠️ **유지보수 규칙**: `.rake` 파일이 추가·삭제되거나 태스크명·적재 데이터가 바뀌면 이 CLAUDE.md와 `db/seeds.rb`(invoke 목록·순서), 그리고 관련 시드 소스(`db/seeds/monsters.yml`)를 함께 확인·갱신하세요.
