# app/controllers/games/ — 독서게임 10종 (7종 온디맨드 실동작 + 3종 스텁)

학생이 즐기는 독서게임 네임스페이스입니다. Phase 3 온디맨드 편입으로 **7종이 실동작**합니다:
`quiz`·`golden`·`bingo`·`classic`(mcq 콘텐츠축) · `vocab`(matching) · `whoami`(hint_reveal) · `balance`(balance_vote).
나머지 3종(`book`·`battle`=R3·`marathon`=R2)은 라우트만 살아 있는 **증분 스텁**입니다.
카탈로그에서 **도서를 골라** 표면을 콘텐츠축으로 접어 `Games::ContentProvider.resolve` 로 즉시 플레이하며(미스=오프라인 즉시, 아동 무대기),
결과는 `Games::AttemptsController` 로 제출·채점되어 포인트·진화·뱃지 연쇄로 이어집니다. 모든 컨트롤러는 `Games::BaseController` 를 상속합니다.

## 파일
- `base_controller.rb` — 네임스페이스 베이스. `CATALOG`(10종 라벨·아이콘·surface·playable 플래그, **7종 playable**) + `load_playable_quiz`(교사 published 퀴즈 id 조회 + QuizPolicy#show? 인가) + **`resolve_on_demand(surface)`**(도서 로드→BookPolicy 인가→`ContentProvider.resolve`→QuizPolicy 밴드/학급 클램프 인가→즉시 반환).
- `catalog_controller.rb` — **게임 카탈로그(`index`, §3.1)**. 실동작 게임 목록 + 카탈로그 도서(추천/고전)를 보여 주는 관문. 표현용 목록이라 `verify_authorized` 스킵(로그인 게이트만).
- `attempts_controller.rb` — 게임 결과 기록(`create`). 채점(`QuizPlay`)→`QuizAttempt` 생성/finalize→`award_points` 후 복귀. **whoami 는 선생성 attempt(`attempt_id`)를 finalize**(서버 힌트수 기준 채점). 답안은 타입별(mcq 인덱스/matching 쌍 해시/hint 텍스트)이라 `to_i` 로 뭉개지 않고 원형(`to_unsafe_h`)만 넘긴다. 온디맨드(system) 판은 표면 play 로, 교사 퀴즈(id)는 원래 show 로 복귀. 실지급 델타 기준 정직한 안내.
- `quiz_controller.rb`·`golden_controller.rb`·`bingo_controller.rb` — mcq 실동작. `show`=교사 published 퀴즈(id), `play`=온디맨드(book_id). UI(4지선다/서바이벌/빙고판)만 다르고 콘텐츠축은 mcq 공유.
- `classic_controller.rb` — 고전 읽기 여행(mcq 온디맨드). `play` 만(book_id).
- `vocab_controller.rb` — 어휘 낚시(matching 온디맨드). `play` 만. 짝짓기 UI.
- `whoami_controller.rb` — **나는 누구게?(hint_reveal 온디맨드, §3.2b)**. `play`(book_id)=리졸브+**attempt 선생성**(reveal_hint 가 :attempt 요구, NOTE #2)→attempt-키 `show` 로 리다이렉트. `show`(=attempt id)=이미 공개한 힌트만 서버 상태에서 렌더(정답·잔여수 무유출). **`reveal_hint`(POST /whoami/:attempt/reveal_hint)**=공개 요청마다 **서버 카운터(attempt.hint_reveals JSON, DB) 1 증가**(세션쿠키 아님 → stale-cookie replay 차단, NOTE #1)→다시 show. 채점은 이 서버 카운트로만(C1).
- `balance_controller.rb` — 밸런스 게임(balance_vote 온디맨드). `play` 만. 무정답 딜레마 투표(참여만, 0점; 참여 포인트는 Phase 4).
- `regenerate_controller.rb` — **다시 뽑기(`create`, §3.4)**. `ContentProvider.regenerate` 로 **새 content_version** 재생성(rate limit·예산 하 워밍 재적재) 후 해당 표면 play 로 복귀. 포인트는 콘텐츠축 상한이 이미 봉인(재생성 파밍 불가). 콘텐츠 재생성이지 가챠·랜덤 획득이 아니므로 경로명은 `games_regenerate_path`(무가챠 라우트 가드 준수).
- `stub_controller.rb` — 증분 게임 공통 플레이스홀더 베이스. "준비 중"(`games/placeholder`) 렌더 + `verify_authorized` 스킵.
- `book_controller.rb`·`battle_controller.rb`·`marathon_controller.rb` — 증분 스텁(`StubController` 상속).

## 패턴·규칙
- **온디맨드 진입**: 카탈로그 → 도서 선택 → `games_<표면>_play_path(book_id:)`. `resolve_on_demand` 가 표면→콘텐츠축 리졸브 + 이중 인가(BookPolicy·QuizPolicy)를 담당. 미스=오프라인 즉시(무대기).
- **경계 클램프(§3.3)**: `QuizPolicy#show?` 가 학생 플레이 시점에 origin 별 경계를 강제(system=band 서버계산 일치, teacher=학급 경계). raw quiz_id(교사/system) 직접 플레이도 여기서 걸러져 **선존 크로스-학급 구멍**을 닫는다. `QuizAttemptPolicy#create?/update?` 가 그 경계를 재사용.
- **서버 채점·무유출(C1)**: 정답키·힌트 공개수는 서버에만. hint_reveal 은 attempt 행의 서버 카운트만 신뢰(클라이언트 주장·위조 무력화).
- **결과 기록**: 채점·포인트는 게임 컨트롤러가 아니라 `attempts#create` 한 곳으로 모인다.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
