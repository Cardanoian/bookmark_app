# app/controllers/games/ — 독서게임 5종 (교육 다양성 우선)

학생이 즐기는 독서게임 네임스페이스입니다. **교육 다양성 우선 5종**만 둡니다:
`quiz`·`classic`(mcq 콘텐츠축, 독해·고전) · `vocab`(matching, 어휘) · `whoami`(hint_reveal, 추론) · `book`(소셜 도메인, 요약·표현).
앞의 4종은 퀴즈 파이프라인(`Games::ContentProvider.resolve`)으로 도서→콘텐츠축을 접어 즉시 플레이하고(미스=오프라인 즉시, 아동 무대기)
결과를 `Games::AttemptsController` 로 제출·채점(포인트·진화·뱃지 연쇄)합니다.
`book`(책 소개 대결)은 **퀴즈 파이프라인 밖 소셜 도메인**으로, Gemini/Quiz 를 만들지 않고 도서별 소개 작성·또래 투표(경계=학급)만 합니다.
모든 컨트롤러는 `Games::BaseController` 를 상속합니다.

## 파일
- `base_controller.rb` — 네임스페이스 베이스. `CATALOG`(5종 라벨·아이콘·surface·playable, **전부 playable**) + `load_playable_quiz`(교사 published 퀴즈 id 조회 + QuizPolicy#show? 인가) + **`resolve_on_demand(surface)`**(도서 로드→BookPolicy 인가→`ContentProvider.resolve`→QuizPolicy 밴드/학급 클램프 인가→즉시 반환).
- `catalog_controller.rb` — **게임 카탈로그(`index`, §3.1)**. playable 게임 목록 + 카탈로그 도서(추천/고전)를 보여 주는 관문. 표현용 목록이라 `verify_authorized` 스킵(로그인 게이트만). 각 게임은 `games_<key>_play_path(book_id:)` 로 진입한다.
- `attempts_controller.rb` — 퀴즈 파이프라인 4종(quiz·classic·vocab·whoami) 결과 기록(`create`). 채점(`QuizPlay`)→`QuizAttempt` 생성/finalize→`award_points` 후 복귀. **whoami 는 선생성 attempt(`attempt_id`)를 finalize**(서버 힌트수 기준 채점). 답안은 타입별(mcq 인덱스/matching 쌍 해시/hint 텍스트)이라 `to_i` 로 뭉개지 않고 원형(`to_unsafe_h`)만 넘긴다. 온디맨드(system) 판은 표면 play 로, 교사 퀴즈(id)는 `games_quiz_path` show 로 복귀(`redirect_target`). 실지급 델타 기준 정직한 안내(`result_notice`).
- `quiz_controller.rb` — mcq 실동작. `show`=교사 published mcq 퀴즈(id), `play`=온디맨드(book_id). 4지선다 UI.
- `classic_controller.rb` — 고전 읽기 여행(mcq 온디맨드). `play` 만(book_id). quiz 와 콘텐츠축(mcq) 공유, 고전 카탈로그 한정이라는 별도 교육 가치로 유지.
- `vocab_controller.rb` — 어휘 낚시(matching 온디맨드). `play` 만. 짝짓기 UI.
- `whoami_controller.rb` — **나는 누구게?(hint_reveal 온디맨드, §3.2b)**. `play`(book_id)=리졸브+**attempt 선생성/재사용**(reveal_hint 가 :attempt 요구; 같은 퀴즈의 **미확정[played_at nil] attempt 는 재사용**해 0점 빈 attempt 누적·힌트 리셋 우회 차단)→attempt-키 `show` 로 리다이렉트. `show`(=attempt id)=이미 공개한 힌트만 서버 상태에서 렌더(정답·잔여수 무유출). **`reveal_hint`(POST /whoami/:attempt/reveal_hint)**=공개 요청마다 **서버 카운터(attempt.hint_reveals JSON, DB) 1 증가**(세션쿠키 아님 → stale-cookie replay 차단)→다시 show. 채점은 이 서버 카운트로만(C1).
- `book_controller.rb` — **책 소개 대결(소셜 도메인, 퀴즈 파이프라인 밖)**. `play`(book_id)=도서 로드 + 같은 학급 소개 목록(득표순) + 작성 폼 + **정적 작성 가이드(`WRITING_TIPS` 상수, Gemini 호출 0)**. `create`=본인·학급으로 소개 작성(`authorize @intro`). `vote`/`unvote`=또래 소개 1인 1표(cheer 패턴, RecordNotUnique rescue). 경계 격리는 `BookIntroPolicy`(크로스-학급 차단). **Quiz/GenerateGameContentJob 를 만들지 않는다**(assert).
- `regenerate_controller.rb` — **다시 뽑기(`create`, §3.4)**. `ContentProvider.regenerate` 로 **새 content_version** 재생성(rate limit·예산 하 워밍 재적재) 후 해당 표면(quiz·classic·vocab·whoami) play 로 복귀. 포인트는 콘텐츠축 상한이 이미 봉인(재생성 파밍 불가). 무가챠 라우트 가드 준수차 경로명은 `games_regenerate_path`.
- `content_reports_controller.rb` — **콘텐츠 신고(`create`, 무게이트 롤아웃 안전장치)**. system(온디맨드) 판만 신고 대상(`quiz_id`), `authorize quiz, :show?`(플레이 경계 안 콘텐츠만) 후 `ContentProvider.record_report!` 로 1인 1신고 기록. 서로 다른 2명(`REPORT_HIDE_THRESHOLD`) 신고 시 자동 숨김+재생성. 접수는 신고자 학급 담임 대시보드로 사후 검토(교사 알림). 결과(중복/접수/숨김)에 맞춘 정직한 안내.

## 패턴·규칙
- **온디맨드 진입(퀴즈 4종)**: 카탈로그 → 도서 선택 → `games_<표면>_play_path(book_id:)`. `resolve_on_demand` 가 표면→콘텐츠축 리졸브 + 이중 인가(BookPolicy·QuizPolicy)를 담당. 미스=오프라인 즉시(무대기).
- **book(소셜) 경계**: `BookIntroPolicy` 가 같은 학급 소개만 열람·투표하게 강제(크로스-학급 차단). 자기 소개 투표 불가, 1인 1표.
- **경계 클램프(§3.3)**: `QuizPolicy#show?` 가 학생 플레이 시점에 origin 별 경계를 강제(system=band 서버계산 일치, teacher=학급 경계). raw quiz_id 직접 플레이도 여기서 걸러진다. `QuizAttemptPolicy#create?/update?` 가 그 경계를 재사용.
- **서버 채점·무유출(C1)**: 정답키·힌트 공개수는 서버에만. hint_reveal 은 attempt 행의 서버 카운트만 신뢰(클라이언트 주장·위조 무력화).
- **결과 기록(퀴즈 4종)**: 채점·포인트는 게임 컨트롤러가 아니라 `attempts#create` 한 곳으로 모인다. book 은 포인트 미지급(소셜).

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
