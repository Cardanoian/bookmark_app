# app/policies — Pundit 인가 정책 (역할·학교/학급 경계 격리)

컨트롤러의 `authorize`·`policy_scope` 호출이 도달하는 Pundit 정책 계층입니다. 5개 role(student·teacher·school_admin·librarian·superadmin)과 학교/학급 소속을 조합해 "누가 무엇을 볼·할 수 있는가"를 판정합니다. 기본은 전부 거부(ApplicationPolicy)이고, 각 정책이 필요한 액션만 열어 줍니다. superadmin은 대체로 전권, 학생은 본인 소유 리소스만, 교사·교무·사서는 담당 학급/학교 경계 안으로 제한됩니다.

## 파일
- `application_policy.rb` — 모든 정책의 베이스. 6개 표준 액션(index·show·create·update·destroy 등)을 기본 `false`로 두고, 내부 `Scope`는 `resolve` 미구현 시 예외. 하위 정책이 필요한 것만 override.
- `report_policy.rb` — 독후감. show/update/Scope를 role별 분기(총괄=전체, 교사=담당 학급, 학생=본인, 교무·사서=같은 학교). destroy/revise=작성 학생 본인, review=담당 교사·총괄. **`approve?` = `review? && record.review_ready?`(BUG_FIX_PLAN F3, 2026-09-20)** — 승인은 되돌릴 수 없는 확정(포인트·뱃지·진화·미션 캐스케이드)이라, 목록·화면이 이미 초안과 준비 중인 글을 걸러도 URL 직접 요청·`batch_approve` id 배열 위조에 대해 정책에서 한 번 더 fail-closed 로 막는다. `submitted?` 만 보던 때는 AI 처리 중인 글이 승인됐고, 그 뒤 저장된 첨삭이 교사가 읽지 않은 채 학생에게 공개됐다. **교사가 확인한 버전과의 대조는 요청값이 필요해 정책이 아니라 `Report#approve!(seen_version:)` 가 한다**(호출부: 일괄 승인은 `approve?` 로 거른 뒤 `approve!`, 단건 승인은 `review?` 로 인가한 뒤 `approve!` 의 결과[`:not_ready`/`:stale`]로 안내한다 — 같은 조건을 `approve!` 가 트랜잭션 안에서 다시 보므로 어느 쪽도 우회하지 못한다). **`share?`** 는 새 공유에 `record.feedback_visible?`(현재 버전의 유효한 승인)를 요구하고 `|| record.shared?` 로 취소 경로는 열어 둔다. **`retry_review?`**(같은 버전으로 첨삭 다시 요청 — 글쓴이·담임·총괄 + `record.review_retryable?`).
- `board_post_policy.rb` — 우수작 게시판. **경계=학교**(2026-09-19): 게시물은 글이 쓰인 학급(`report.classroom`)의 학교 구성원에게만 보이고 총괄만 전체를 본다. 게시판은 실명과 독후감 전문을 보여 주므로, 여러 학교가 한 서버를 쓸 때 다른 학교로 넘어가지 않게 한 것이다(그전에는 학교 경계 없이 전원 공개). 숨김(hidden) 글은 같은 학교의 모더레이터(교사·교무)와 총괄만 열람. Scope 도 같은 기준(`joins(report: :classroom)`)이며, 학생 홈의 '친구들의 우수작'(`StudentHomeQuery#featured_board_posts`)도 이 Scope 를 그대로 쓴다.
- `book_policy.rb` — 도서 카탈로그·검색. 열람·검색 모두 로그인 사용자.
- `book_intro_policy.rb` — 책 소개 대결. **경계=학급**: 소개 작성은 학급 소속 학생(`create?`), 투표는 같은 학급 또래의 소개만(`vote?`, 자기 소개 제외), 회수는 본인 학급 내(`unvote?`). Scope 는 본인 학급 소개만 노출(크로스-학급 열람·투표 차단).
- `book_sequel_policy.rb` — 뒷이야기 이어쓰기(BookIntroPolicy 미러). **경계=학급**: 작성은 학급 소속 학생(`create?`), 공감은 같은 학급 또래의 글만(`vote?`, 자기 글 제외), 회수는 본인 학급 내(`unvote?`). Scope 는 본인 학급 뒷이야기만 노출(크로스-학급 열람·공감 차단).
- `account_link_policy.rb` — 계정 연동(MERGE) 학생 셀프서브(account_linking_seasons_plan §Phase 3, BookIntroPolicy 미러). `new?/preview?/confirm? = user.student? && user.classroom_id.present?`(교사·비학급·비로그인 차단). Scope 불필요(심볼 정책 `authorize :account_link, ...`). 실제 병합 가드(작년 계정 소유증명·학년도 경계·정지·동시성)는 정책이 아니라 `Accounts::MergeService`가 트랜잭션에서 강제한다.
- `challenge_policy.rb` — 챌린지. **열람(`show?`)은 Scope 와 대칭인 전국+소속학교 경계**(총괄=전체, 그 외=global 챌린지 또는 소속 학교 school 챌린지만 — 컨트롤러 show 가 `authorize @challenge` 레코드 기반이라 타 학교 school 챌린지 상세 조회 시 `EvaluateProgress` 크로스-스쿨 지연 참여·보상 생성 차단), 참여(join)는 학생 + **manage?(교직원=staff)**, `new?`/`create?` = manage?, `edit?`/`update?`/`destroy?` = **manage_record?**(총괄=전권, 교사·사서·교무는 **우리 학교의 학교스코프 챌린지만** — global·타교 챌린지는 총괄만) + **Scope**(총괄=전체, 그 외 로그인=전국+소속학교, 비로그인=none).
- `cheer_policy.rb` — 응원. 학생만 생성하되 대상 게시물이 보이는(BoardPostPolicy#show?) 경우만. 취소는 본인 응원만.
- `classroom_policy.rb` — 학급. show/Scope를 role별 분기(총괄=전체, 교사=담임 학급, 학생=소속 학급, 교무·사서=같은 학교).
- `forum_post_policy.rb` — 토론 글. 대상 토픽을 열람 가능(TopicPolicy#show?)한 사용자만 작성.
- `forum_post_like_policy.rb` — 토론 글 좋아요. 생성은 대상 토픽 열람 가능(TopicPolicy#show?)한 사용자만, 취소는 본인 좋아요만.
- `forum_post_report_policy.rb` — 토론 글 신고(reading_discussion). 대상 토픽 열람 가능(TopicPolicy#show?) + **자기 글이 아닐 때만** 신고(`record.forum_post.user_id != user.id`). (교사 수동 숨김은 정책이 아니라 `Teacher::ForumModerations`가 `owned_student!`로 저자 학급 경계를 강제.)
- `learn_policy.rb` — 단계 학습 위저드. **학생만**(index·advance, 2026-09-13) — 마치면 독후감 초안을 만들고(ReportPolicy#create? 도 학생만) 진행을 학생 행(`LearnWizardProgress`)에 남긴다. 로그인만 보던 때는 진행이 DB 행이 된 뒤 담임이 몇 단계 답하다 마지막에 막히면 고아 진행 행이 남았다. 앱 화면에 교직원 진입점은 없다.
- `mission_policy.rb` — 미션. **`show?`는 역할별 학급 경계**(총괄=전체, 교사=담당 학급[`record.classroom.teacher_id == user.id`], 학생=자기 학급+발행[`record.classroom_id == user.classroom_id && record.published?`], 교무·사서=같은 학교) — 최상위 `MissionsController#show`(학생 미션 상세 열람)의 크로스-학급·크로스-학교 열람을 차단(report_policy role-case 미러; 교사는 `classroom_id` nil 이라 학생 규칙 재사용 금지). 참여(join)는 학생.
- `monster_policy.rb` — 몬스터. 도감 열람은 로그인 사용자, 진화·대표지정·먹이주기는 보유자 본인만(owns_record?).
- `purchase_policy.rb` — 구매. 학생 본인만 생성.
- `quiz_contribution_policy.rb` — 학생 출제 기여(전국 공유 문제은행 Phase 3 §4). **작성(출제)은 학급 소속 학생 본인만**(`create?`/`new?` = `user.student? && classroom_id`, BookIntroPolicy 미러). 교사·비학급·비로그인 불가. **`index?`(내가 낸 문제 모아보기)는 `user.student?` 만 요구**한다 — 목록은 컨트롤러가 `current_user.quiz_contributions` 로 본인 것만 조회하므로 정책은 역할만 판정하고, 새 기여를 만들지 않으니 `create?` 와 달리 학급 소속을 요구하지 않는다(학급이 없어진 학생도 과거 기여는 되돌아볼 수 있어야 한다). 교사 검토·수정·승인/반려 경계는 정책이 아니라 `Teacher::QuizContributionsController`가 `owned_student!`로 강제한다(담임이 자기 학급 학생 기여만 — 크로스-학급 403).
- `quiz_policy.rb` — 퀴즈. published 퀴즈 열람·플레이 + 생성·수정은 교사·총괄만(manage?). **경계 클램프(Phase 3 §3.3, N2/#2/#3)**: 학생 `show?` 는 origin 별로 플레이 경계를 강제한다 — **system**(온디맨드 캐시)은 `record.band == game_band_for(학급 학년)` 서버계산 일치(다른 band 행을 id 로 치면 403; **학년 미상 학생은 최저 밴드 g12** 로 고정 — 리졸버와 동일 함수라 생성=인가 밴드 일치), **teacher** 는 학급-스코프 퀴즈면 소속 학급만(전역은 전체). raw quiz_id 경로에도 적용되어 **선존 크로스-학급 published 퀴즈 id 플레이 구멍**을 닫는다. 교사·총괄은 클램프 면제(미리보기/관리). Scope 도 동일.
- `quiz_attempt_policy.rb` — 퀴즈 플레이 기록. `create?`(제출)·`update?`(whoami 힌트 공개)는 **대상 퀴즈의 플레이 경계를 QuizPolicy#show? 로 위임**해 한 곳에서 강제(band/학급 클램프 재사용). `update?` 는 본인 attempt 이면서 플레이 가능해야 함. 열람은 본인 기록만.
- `ranking_policy.rb` — 랭킹. 학생만 열람하며, 실제 참여 여부(`ranking_opted_in`)는 `RankingsController`가 설정 화면 리다이렉트로 추가 강제한다.
- `sticker_policy.rb` — 문장 스티커. 학생만 생성하되 대상 report의 게시물이 보이는 경우만.
- `topic_policy.rb` — 토론방. 경계는 **역할별로 다르다**: 학생=자기 학급(`record.classroom_id == user.classroom_id`)+자기 학교, **교사=담당 학급(`Classroom.teacher_id == user.id`, 다학급 가능)+자기 학교**(교사는 `user.classroom_id`가 nil이라 학생 규칙 재사용 불가 — 이 분기가 없으면 담임이 자기 반 토픽을 못 봄), 총괄=전체. 생성은 학생·교사. Scope도 역할별 classroom_ids 로 경계 필터링.

## 패턴·규칙
- **기본 거부**: `ApplicationPolicy`가 모든 액션을 `false`로 시작한다. 정책은 열어 줄 액션만 명시적으로 override한다.
- **역할 분기 관용구**: 경계가 복잡한 정책(report·classroom·topic·quiz)은 `case user.role.to_sym`으로 총괄/교사/학생/교무·사서를 나눠 판정한다. 단순 정책은 `user&.student?` 같은 술어 헬퍼로 끝낸다.
- **학교/학급 경계 격리**: `record.school_id == user.school_id`·`record.classroom&.teacher_id == user.id` 등 소속 비교로 다른 학교·학급 데이터 접근을 차단한다. `same_school?`·`teacher_of_classroom?`·`within_boundary?` private 헬퍼가 그 판정을 담는다.
- **Scope로 목록 필터링**: 목록(index)은 `authorize`가 아니라 `policy_scope`가 안전하다. 내부 `Scope#resolve`는 로그인 없으면 `scope.none`, 역할별로 `where`를 좁혀 애초에 경계 밖 레코드를 쿼리에서 배제한다.
- **정책 재사용(위임)**: 종속 리소스는 상위 정책의 show?를 재호출한다 — cheer·sticker는 `BoardPostPolicy#show?`, forum_post·forum_post_like는 `TopicPolicy#show?`로 "볼 수 있어야 상호작용 가능" 규칙을 한 곳에서 강제한다.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
