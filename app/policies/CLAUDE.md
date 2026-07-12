# app/policies — Pundit 인가 정책 (역할·학교/학급 경계 격리)

컨트롤러의 `authorize`·`policy_scope` 호출이 도달하는 Pundit 정책 계층입니다. 5개 role(student·teacher·school_admin·librarian·superadmin)과 학교/학급 소속을 조합해 "누가 무엇을 볼·할 수 있는가"를 판정합니다. 기본은 전부 거부(ApplicationPolicy)이고, 각 정책이 필요한 액션만 열어 줍니다. superadmin은 대체로 전권, 학생은 본인 소유 리소스만, 교사·교무·사서는 담당 학급/학교 경계 안으로 제한됩니다.

## 파일
- `application_policy.rb` — 모든 정책의 베이스. 6개 표준 액션(index·show·create·update·destroy 등)을 기본 `false`로 두고, 내부 `Scope`는 `resolve` 미구현 시 예외. 하위 정책이 필요한 것만 override.
- `report_policy.rb` — 독후감. show/update/Scope를 role별 분기(총괄=전체, 교사=담당 학급, 학생=본인, 교무·사서=같은 학교). revise=작성자 본인, review/approve/verify=담당 교사·총괄.
- `board_post_policy.rb` — 우수작 게시판. 숨김(hidden) 글은 모더레이터(교사·교무·총괄)만 열람. Scope도 동일 기준.
- `book_policy.rb` — 도서 카탈로그·검색. 열람·검색 모두 로그인 사용자.
- `book_intro_policy.rb` — 책 소개 대결. **경계=학급**: 소개 작성은 학급 소속 학생(`create?`), 투표는 같은 학급 또래의 소개만(`vote?`, 자기 소개 제외), 회수는 본인 학급 내(`unvote?`). Scope 는 본인 학급 소개만 노출(크로스-학급 열람·투표 차단).
- `challenge_policy.rb` — 챌린지. 열람은 로그인 사용자, 참여(join)는 학생.
- `cheer_policy.rb` — 응원. 학생만 생성하되 대상 게시물이 보이는(BoardPostPolicy#show?) 경우만. 취소는 본인 응원만.
- `classroom_policy.rb` — 학급. show/Scope를 role별 분기(총괄=전체, 교사=담임 학급, 학생=소속 학급, 교무·사서=같은 학교).
- `forum_post_policy.rb` — 토론 글. 대상 토픽을 열람 가능(TopicPolicy#show?)한 사용자만 작성.
- `learn_policy.rb` — 단계 학습 위저드. 로그인 사용자면 진행(index·advance).
- `mission_policy.rb` — 미션. 열람은 로그인 사용자, 참여(join)는 학생.
- `monster_policy.rb` — 몬스터. 도감 열람은 로그인 사용자, 진화·대표지정·먹이주기는 보유자 본인만(owns_record?).
- `purchase_policy.rb` — 구매. 학생 본인만 생성.
- `quiz_policy.rb` — 퀴즈. published 퀴즈 열람·플레이 + 생성·수정은 교사·총괄만(manage?). **경계 클램프(Phase 3 §3.3, N2/#2/#3)**: 학생 `show?` 는 origin 별로 플레이 경계를 강제한다 — **system**(온디맨드 캐시)은 `record.band == game_band_for(학급 학년)` 서버계산 일치(다른 band 행을 id 로 치면 403; **학년 미상 학생은 최저 밴드 g12** 로 고정 — 리졸버와 동일 함수라 생성=인가 밴드 일치), **teacher** 는 학급-스코프 퀴즈면 소속 학급만(전역은 전체). raw quiz_id 경로에도 적용되어 **선존 크로스-학급 published 퀴즈 id 플레이 구멍**을 닫는다. 교사·총괄은 클램프 면제(미리보기/관리). Scope 도 동일.
- `quiz_attempt_policy.rb` — 퀴즈 플레이 기록. `create?`(제출)·`update?`(whoami 힌트 공개)는 **대상 퀴즈의 플레이 경계를 QuizPolicy#show? 로 위임**해 한 곳에서 강제(band/학급 클램프 재사용). `update?` 는 본인 attempt 이면서 플레이 가능해야 함. 열람은 본인 기록만.
- `ranking_policy.rb` — 랭킹. 로그인 사용자면 열람.
- `sticker_policy.rb` — 문장 스티커. 학생만 생성하되 대상 report의 게시물이 보이는 경우만.
- `topic_policy.rb` — 토론방. 학생·교사는 자기 학급-스코프 또는 자기 학교-스코프 토픽만 열람(경계 밖 차단). 생성은 학생·교사. Scope로 경계 필터링.

## 패턴·규칙
- **기본 거부**: `ApplicationPolicy`가 모든 액션을 `false`로 시작한다. 정책은 열어 줄 액션만 명시적으로 override한다.
- **역할 분기 관용구**: 경계가 복잡한 정책(report·classroom·topic·quiz)은 `case user.role.to_sym`으로 총괄/교사/학생/교무·사서를 나눠 판정한다. 단순 정책은 `user&.student?` 같은 술어 헬퍼로 끝낸다.
- **학교/학급 경계 격리**: `record.school_id == user.school_id`·`record.classroom&.teacher_id == user.id` 등 소속 비교로 다른 학교·학급 데이터 접근을 차단한다. `same_school?`·`teacher_of_classroom?`·`within_boundary?` private 헬퍼가 그 판정을 담는다.
- **Scope로 목록 필터링**: 목록(index)은 `authorize`가 아니라 `policy_scope`가 안전하다. 내부 `Scope#resolve`는 로그인 없으면 `scope.none`, 역할별로 `where`를 좁혀 애초에 경계 밖 레코드를 쿼리에서 배제한다.
- **정책 재사용(위임)**: 종속 리소스는 상위 정책의 show?를 재호출한다 — cheer·sticker는 `BoardPostPolicy#show?`, forum_post는 `TopicPolicy#show?`로 "볼 수 있어야 상호작용 가능" 규칙을 한 곳에서 강제한다.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
