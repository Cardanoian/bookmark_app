# 계정 연동(MERGE) + 랭킹 시즌제 — 상세 구현 계획

> **상태: PENDING APPROVAL** (ralplan consensus · deliberate mode). 실행 전 사용자 승인 대기.
> **합의 기록**: Planner 초안 → Architect(SOUND-WITH-CHANGES) → Critic(ITERATE) → v2 개정 → Architect 재검토(신규 3건) → v3 개정 → **Critic APPROVE**(잔여는 비차단 MINOR 4건, 구현 중 반영).
> 이 문서는 계획 아티팩트입니다. 승인 전까지 소스 변경·마이그레이션·커밋은 하지 않습니다.

## 0. 개요

학급에 `academic_year`가 도입되면서, 학년이 바뀌면 새 담임이 **새 학생 계정**을 만들고 작년 활동(독후감·몬스터·포인트·경험치·뱃지)이 옛 `user_id`에 고아로 남는다. 두 기능으로 해결한다.

- **A. 계정 연동(MERGE)**: 기록 있는 **옛 계정을 생존자**로, 새 placeholder 계정을 접어 삭제하고 세션을 생존자로 스왑한다. 생존자가 새 계정의 학급·학교·이름·비번을 승계한다. 학생 셀프서브(마이페이지, 작년 자격증명 로그인 증명) + 교사/총괄 보조 + 감사 + 시간창 되돌리기.
- **B. 랭킹 시즌제**: 시즌 = `academic_year`(연 1회, `Classroom.current_academic_year` 단일 진실). 평생 카운터(experience/points/레벨/명예의전당)는 불변으로 이월하고, 랭킹만 `season_scores.experience_earned`로 분리해 매 학년도 0에서 재출발한다.

두 기능은 상보적이다: 병합은 **평생 자산만** 잇고, 시즌 점수는 이월하지 않아 학년 경계에서 자연히 리셋된다.

---

## 1. RALPLAN-DR 요약

### 1.1 원칙 (Principles)
1. **단일 초크포인트 불변** — 포인트/경험치 변동은 `Pointable`의 `award_points`·`credit_points!`·`revoke_points!`만 경유. 시즌 훅도 이 3곳에만.
2. **평생 자산 불변 / 시즌은 파생 측정치** — `users.experience`(레벨·진화·전당 근거)·`users.points`(진화 비용)는 리셋 금지. 랭킹은 `season_scores.experience_earned`로 분리. 임포트 초기 experience는 시즌 **미시딩**(0 시작).
3. **머지는 원자적·가역적·감사가능** — 전 과정 단일 `ApplicationRecord.transaction`; `account_merges` 원장에 **이동행 매니페스트 + pre-merge 스냅샷** + counter 재계산으로 실질 가역. dedup으로 삭제된 중복행은 **불가역**(명문), 병합-후 생존자 활동은 되돌려도 **잔류**.
4. **머지 인증 = 브루트포스 표면** — 연동 로그인은 Sessions fail2ban 재사용하되 **계정 축 공유 + IP 축 분리**. 확인화면·**fail-closed 일회성 가드**·감사·되돌리기 동반.
5. **경계·롤아웃 격리** — `owned_student!`·per-action Pundit + `AppSetting.feature_enabled?` 스코프 플래그. 읽기 플래그 `ranking_seasons`는 **2027-03 학년도 경계**에 전역 on(2026 시즌=부분·비권위).

### 1.2 결정 동인 (Drivers)
데이터 이동·충돌 최소화 / 아동 안전·오남용 저항 / 게임 루프 무회귀.

### 1.3 채택안 (Options·확정)
- **(a) 머지 생존 방향** = OLD 생존자, NEW placeholder 소비/삭제 + 세션 스왑 + 생존자가 NEW 신원 승계. (NEW 생존 방향은 대량 자식행 복사·충돌 과다·`classroom_id` 파생 로스터 원칙 위배로 기각.)
- **(b) 시즌 키잉** = `season_scores.academic_year` 정수 직접 키잉. (미사용 `Season` 모델 확장은 복잡성으로 기각, 테이블은 드롭 않고 방치 — 후속 정리 후보.)
- **(c) 되돌리기** = 시간창(14일; 총괄 무제한) **감사-스냅샷 역머지**. (소프트락=유령계정·유니크 충돌, 하드삭제-only=회복불가로 기각.)

### 1.4 Pre-mortem (6 시나리오 + 완화)
1. **머지 경쟁/부분 실패** → 단일 트랜잭션 + 유니크 하드차단 + raw `delete_all` + 커밋 후에만 세션/방송 + `PRAGMA foreign_key_check` 테스트.
2. **구비번 브루트포스 탈취** → 계정 축 공유 + IP 축 분리 스로틀, 정답-우선, 랜덤 10자 임시비번, 확인화면, 감사+되돌리기, 교사 `owned_student!`.
3. **시즌 이중집계/누락** → 3 초크포인트 + `[academic_year,user_id]` 유니크 + upsert 원자증가 + sum-and-delete + `seasons:reconcile` rake.
4. **되돌리기-후-활동 귀속** → 매니페스트가 pre-merge 이동행만 스탬프; reverse는 매니페스트 행만 원복, 병합-후 활동은 생존자 잔류(귀속 규칙·왕복 테스트).
5. **동일 OLD 동시 이중병합** → step7 **조건부 claim**(`WHERE classroom_id/school_id = token`, affected 0→rollback) + `account_merges` `consumed_user_id WHERE reversed_at IS NULL` 부분 유니크 + SQLite 쓰기 직렬화. read-then-write 금지.
6. **flag 반쪽 롤아웃 skew** → 훅 즉시 배포(축적), 읽기 flag는 2027-03 전역 on, 2026 부분 시즌 비권위 문서화, 스코프 오버라이드는 파일럿 한정, 롤아웃 런북 + reconcile rake.

### 1.5 확장 테스트 계획 (범주)
- **Unit**: SeasonScore·AccountMerge·Pointable(시즌 훅·spend 불변·임포트 미시딩)·MergeService 충돌 전수·RankingBoard.
- **Integration**: account_links(셀프)·teacher/admin_account_links·정책·rankings(grade·시즌·방송).
- **E2E**: 3년 체인·전학·연중 연동·2027-03 시즌 롤오버.
- **Observability**: `account_merges` 원장·`PRAGMA foreign_key_check`·스로틀 히트·`account_links:audit`/`seasons:reconcile` rake.

---

## 2. Phase 순서 (각 독립 출하·테스트 가능)

> 마이그레이션 번호는 최신 #38 `20260721000002` 다음. 스키마 테이블 40 → 42.

### Phase 0 — 시즌 스키마 + Pointable 훅 (additive, 읽기 무변경)

**마이그레이션 `20260722000001_create_season_scores.rb`** (테이블 40→41)
- 컬럼: `academic_year:int NOT NULL`, `user_id:int NOT NULL`, `experience_earned:int default 0 NOT NULL`, `points_earned:int default 0 NOT NULL`, `school_id:int`, `classroom_id:int`, `grade:int`(스냅샷), `timestamps`.
- 인덱스: **`[academic_year, user_id] UNIQUE`(`index_season_scores_identity`) 단 1개.** (죽은 인덱스 `[academic_year,classroom_id]`·`[…,school_id]`·`[…,grade]` **넣지 않음** — RankingBoard는 스냅샷이 아니라 현재 소속 `users.classroom_id`/`school_id`로 group함, `ranking_board.rb:37,55`.)
- 스냅샷 3컬럼에 주석: **"감사/과거 시즌 재현 전용 — 랭킹 그룹핑 키가 아님."**
- FK: `user_id → users on_delete: :cascade`.

**모델 `app/models/season_score.rb`**: `belongs_to :user`; `validates academic_year/user_id presence`, `experience_earned/points_earned >= 0`; `scope :for_year`.

**Pointable 훅 (`app/models/concerns/pointable.rb`)**
- private `increment_season_score!(experience:, points:)`: `return unless respond_to?(:student?) && student? && classroom_id`. `year = Classroom.current_academic_year`. **raw SQLite upsert-원자증가**(트랜잭션 안전): `INSERT ... ON CONFLICT(academic_year,user_id) DO UPDATE SET experience_earned = experience_earned + excluded.experience_earned, points_earned = points_earned + excluded.points_earned`(스냅샷 컬럼은 최초 삽입 시에만).
- `award_points`: `update_counters` 직후 `increment_season_score!(experience: amount, points: amount)`.
- `credit_points!`: `update_counters` 직후 동일 호출(트랜잭션 안, 방송·reload 없음 — 대칭).
- `revoke_points!`: `experience_earned = MAX(experience_earned - amount, 0)` 하향.
- `spend_points!`: **무변경**(시즌 경험치는 소비로 감소 안 함).
- `initialize_experience_from_points`: **시즌 미시딩**(임포트 초기 experience는 시즌 0 유지).
- *검증 근거*: `award_points`는 `credit_points!`를 내부 호출하지 않고 둘 다 `update_counters` 직접 호출 → 시즌 이중계수 없음. Rewarder는 `credit_points!`만, `affected!=1`이면 미호출 → 롤백 정합.

### Phase 1 — RankingBoard 시즌 전환 + grade + 방송/뷰 + 읽기 플래그

**`app/services/ranking_board.rb`** — 현재 학년도 season_scores를 라이브 멤버십에 LEFT JOIN:
- `class_ranking`: `classroom.users.where(role: :student)` LEFT JOIN `season_scores ON user_id=users.id AND academic_year=<current>` → `COALESCE(experience_earned,0) AS season_experience`, `ORDER BY season_experience DESC, name ASC`. `[academic_year,user_id]` 유니크만 사용.
- `school_ranking`/`nation_ranking`: 위 per-user 조인 후 **현재 소속(`users.classroom_id`/`school_id`)으로 group + `SUM(experience_earned)`**. 스냅샷 컬럼 미사용.
- `grade_ranking`(신규): 뷰어 학교 + `classroom.grade`(현재 소속) 개인 순위.
- `podium` = `class_ranking.first(3)`. `challenge_ranking`·`hall_of_fame` **무변경**(전당은 평생 도감+진화).
- 읽기 플래그: `AppSetting.feature_enabled?("ranking_seasons", scope:, default: false)`. off면 평생 `experience` 폴백. 데이터(Phase 0)는 플래그 무관 항상 축적.

**방송/뷰**: `Pointable#broadcast_ranking_change`가 `season_experience` 로컬 전달. `app/views/rankings/_ranking_row.html.erb`·`_podium`이 시즌 값 표시(executor가 파셜 실물 확인). `rankings_controller.rb` `grade` 탭 추가(class/school/nation/**grade**/challenge/hall).

### Phase 2 — 머지 코어: 감사 테이블 + `Accounts::MergeService`

**마이그레이션 `20260722000002_create_account_merges.rb`** (테이블 41→42)
- 컬럼: `surviving_user_id:int NOT NULL`, `consumed_user_id:int`(삭제될 placeholder — FK 없이 감사 보존, **역사적 원 id 불변**), `performed_by_id:int`, `performed_by_role:int`, `from/to_classroom_id`, `from/to_school_id`, `moved_counts:json`, `snapshot:json`(매니페스트+pre-merge), `reversed_at:datetime`, `reversed_by_id:int`, `timestamps`.
- 인덱스: `[surviving_user_id]`, `[consumed_user_id]`, `[reversed_at]`, **부분 유니크 `consumed_user_id WHERE reversed_at IS NULL`**(1회 소비 idempotency, fail-closed).
- FK: `surviving/performed/reversed_by → users on_delete: :nullify`.

**모델 `app/models/account_merge.rb`**: `belongs_to :surviving_user, class_name: "User", optional: true`; `scope :active`(`reversed_at IS NULL`); `reverse!`(Phase 4).

**서비스 `app/services/accounts/merge_service.rb`** — `initialize(old_account:, new_account:, performed_by:)`. old=생존자, new=현재 placeholder. `preview`(부작용 없이 카운트). `call`(단일 트랜잭션).

#### dedup 대상 테이블

| # | 테이블 | 유니크 | counter_cache 부모 | dedup 방식 |
|---|--------|--------|--------------------|-----------|
| 1 | `user_monsters` | `[user_id, dex_no]` | — | **in-place 승격**: dex 충돌 시 stage 비교 — NEW 우월이면 `UPDATE user_monsters SET monster_species_id=<NEW species>, evolved_at=<NEW>, updated_at=now WHERE id=<OLD 그 dex 행>` 후 NEW행 DELETE; OLD 우월/동률이면 NEW행만 DELETE. `celebrated_at`은 승격 OLD행 보존. 충돌 없는 dex는 단순 이관. (OLD 행 id 불변 → `OLD.active_monster_id` 보존.) |
| 2 | `user_badges` | `[user_id, badge_id]` | — | 생존자 우선 |
| 3 | `game_plays` | 부분유니크 2종 `[game_type,book_id,played_on]`/`[game_type,played_on]` | — | 생존자 우선(EXISTS 분기) |
| 4 | `mission_participations` | `[mission_id, user_id]` | — | 생존자 우선 |
| 5 | `cheers` | `[board_post_id, user_id]` | **`reports.cheers_count`(비표준)** | 생존자 우선 + **커스텀 재집계** |
| 6 | `book_intro_votes` | `[book_intro_id, user_id]` | `book_intros.votes_count` | 생존자 우선 + `reset_counters` |
| 7 | `book_sequel_votes` | `[book_sequel_id, user_id]` | `book_sequels.votes_count` | 생존자 우선 + `reset_counters` |
| 8 | `forum_post_likes` | `[forum_post_id, user_id]` | `forum_posts.likes_count` | 생존자 우선 + `reset_counters` |
| 9 | `forum_post_reports` | `[forum_post_id, user_id]` | `forum_posts.reports_count` | 생존자 우선 + `reset_counters` + hide 미재평가 |
| 10 | `quiz_reports` | `[quiz_id, user_id]` | `quizzes.reports_count` | 생존자 우선 + `reset_counters` + hide 미재평가 |

**단순 이관(UPDATE user_id만)**: `quiz_attempts`, `reports`(+`classroom_id` 스냅샷·`revision_of_id` 유지), `forum_posts`, **`book_intros`·`book_sequels`**(user_id NOT NULL + RESTRICT — 미이관 시 placeholder 삭제 FK abort), `quiz_contributions`, `stickers`(`by_user_id`), `recommendation_imports`(`imported_by_id`). `board_posts`는 report 따라감.

**#9/#10 hide 미재평가**: 서로 다른 2명 신고로 발동한 자동숨김은 병합으로 신고자 2→1이 되어도 **자동 해제 안 함**(sticky, 교사 사후검토가 진실). counter만 재계산, 플래그 불변 — 테스트로 계약 고정.

#### 트랜잭션 알고리즘 (step 1~8)
1. **가드(사전점검)**: `old.student? && new.student?`; `old != new`; `old.classroom.academic_year < current`; `new.classroom.academic_year == current`; 둘 다 미정지.
2. **매니페스트·스냅샷 캡처**: 테이블별 이동 행 id 목록(또는 `merge_id` 스탬프) + old의 pre-merge `classroom_id/school_id/name/password_digest/mode/points/experience/active_monster_id` + academic_year별 시즌 스냅샷 + new 전체 속성 + dedup 삭제될 중복 id(불가역 표시) → `account_merges.snapshot`(JSON).
3. **active_monster 해제(NEW쪽만)**: `UPDATE users SET active_monster_id = NULL WHERE id = NEW_ID`. (OLD active 행은 in-place 승격으로 삭제 안 되므로 불건드림.)
4. **자식 재부모화(위 표)** — 유니크 테이블 set-based 2스텝: (a) counter 테이블은 삭제 전 영향 부모 id 수집; (b) 충돌 삭제(`user_monsters`는 in-place 승격); (c) 나머지 `UPDATE user_id=OLD`.
5. **counter 재계산**: 표준 5종 `reset_counters`(예 `BookIntro.reset_counters(id, :book_intro_votes)`); **`cheers_count`는 커스텀** — 부모=`report`, 소스=`board_post.cheers.count`로 `report.update_columns(cheers_count: board_post.cheers.count)`(검증·콜백 우회로 무관 report abort 방지). `forum_posts`는 likes·reports 둘 다.
6. **평생 합산 + 시즌 sum-and-delete**: `UPDATE users SET experience += <new.exp>, points += <new.points> WHERE id=OLD`. 시즌: NEW 현재 학년도 행을 `ON CONFLICT DO UPDATE experience_earned += ...` 로 OLD에 합산 후 `DELETE season_scores WHERE user_id=NEW`.
7. **placeholder 삭제 + 조건부 claim 승계**: raw `User.where(id: NEW_ID).delete_all`(**`.destroy` 금지** — `dependent: :destroy` 10개 CASCADE 소실 방지; 미이관 시 RESTRICT/CASCADE abort=fail-closed). 그 후 `UPDATE users SET classroom_id/school_id/name/password_digest/mode = <new> WHERE id=OLD AND classroom_id=<token.old_classroom> AND school_id=<token.old_school>`. **affected 0→raise 롤백**(동시 이중병합 차단). placeholder 선삭제로 `[school_id,classroom_id,name]` 유니크 미충돌.
8. **감사 기록**: `AccountMerge.create!(...)`.
- **커밋 후(컨트롤러)**: `survivor.run_point_side_effects!`(reload·뱃지·진화·시즌 방송) + `MonsterUnlock.evaluate!(survivor)`(멱등) + 세션 스왑.

### Phase 3 — 학생 셀프서브 UI + 스로틀 + 플래그

**라우트**: `resource :account_link, only: [:new], controller: "account_links"` + `post :preview`·`post :confirm`.

**`app/controllers/account_links_controller.rb`**(per-action Pundit): `require_login` + `require_account_linking!`(플래그 게이트). `new`(폼). `preview`(POST): 스로틀 하 인증 → `MergeService#preview` → 확인화면 + `MessageVerifier` 서명 토큰 `{new_id, old_id, exp: 5.min}` hidden. `confirm`(POST): 토큰 검증 → 가드 → `MergeService#call` → **`handle_authenticated`와 동일 redirect 패턴**: `reset_session; session[:user_id]=survivor.id; redirect_to profile_path`(CSRF rotate 전파, **turbo_stream in-place 금지**) + `run_point_side_effects!`.

**스로틀 concern `app/controllers/concerns/login_throttling.rb`**: SessionsController의 `IP_THROTTLE`/`ACCOUNT_THROTTLE`/`login_limiter`/`locked_out?`/`register_login_failure`/`reset_login_failures` 이관. **class-seam은 `included do class_attribute :rate_limit_store, instance_accessor: false end`로** (각 컨트롤러 독립 접근자). 축 정책:
- **계정 축 공유**: `login:account:<old.user.id>`(Sessions와 동일 키 — 자격증명 브루트포스 표면 합산).
- **IP 축 분리**: `linkauth:ip:<remote_ip>`(별도 네임스페이스 — NAT 로그인 가용성 오염 방지).
- 정답-우선(성공 시 두 축 리셋). SessionsController 리팩터는 동작 불변(기존 sessions 스로틀 테스트가 회귀 가드).

**정책 `app/policies/account_link_policy.rb`**: `new?/preview?/confirm? = user.student? && user.classroom_id.present?`(BookIntroPolicy 미러).

**뷰 `app/views/account_links/`**: `new`(학교 피커 + **작년 학년도 기본** + 이름 + 비번). `preview`(확인화면: "작년 N학년 M반 XXX — 독후감 N·몬스터 M·1,240P·Lv.k를 가져옵니다" + 서명 토큰 + 되돌리기 안내). **마이페이지 진입점** `app/views/profiles/show.html.erb` 계정 섹션(플래그 on + 학급 학생, 이미 연동 시 숨김).

### Phase 4 — 교사/총괄 보조 + 되돌리기(reverse!)

**교사 `app/controllers/teacher/account_links_controller.rb`**(`Teacher::BaseController`, `require_teacher!`): `index`/`new`(담임 학급 현재 학생 선택 + 후보 작년 계정 이름검색, `owned_student!(new_account)` 강제)·`create`(`MergeService#call` 공유, 세션 스왑 없음).

**총괄 `app/controllers/admin/account_links_controller.rb`**: `index`(검색·감사)·`create`·`reverse`.

**`AccountMerge#reverse!`**(14일; 총괄 무제한) — 트랜잭션:
1. **생존자 신원 복원(선행)**: OLD를 pre-merge tuple로 되돌림(`classroom_id/school_id/name/password_digest/mode`, `experience -= 합산분`, `points -= 합산분`, `active_monster_id = pre-merge OLD`) → NEW tuple 해제.
2. **placeholder 삽입**: snapshot의 NEW 속성으로 재삽입. **원 id 재사용은 "id 공백 AND tuple 공백" 둘 다일 때만**; 아니면 새 id + 매니페스트 `user_id`/`by_user_id`/`imported_by_id` 리매핑(rowid 재점유 방지).
3. **매니페스트 자식행 원복**: 스탬프된 pre-merge 이동행만 NEW(또는 리매핑 id)로. 병합-후 활동은 생존자 잔류(귀속 규칙).
4. **counter 재계산**: 표준 5종 `reset_counters` + `cheers_count` 커스텀(step5와 동일).
5. **시즌 역연산**: 스냅샷으로 생존자 현재 시즌 차감 + NEW 시즌 행 재생성.
6. **`reversed_at`/`reversed_by_id` 스탬프**.
- **명문 계약**: 복원 가능(이동행·생존자 pre-merge 속성/카운터/시즌); **불가역**(dedup 삭제 중복행 — user_monsters 열등 개체·중복 vote/like/report/cheer·중복 game_play); 귀속(병합-후 활동 잔류). 새 id 발급 시 되돌린 계정 보유자는 **신규 로그인 필요**(운영 문서 기재).

### Phase 5 — 롤아웃 + 관측
- 시드: `account_linking => false`, `ranking_seasons => false`(2027-03 경계에 on). `admin/settings` 노출.
- rake: `lib/tasks/account_links.rake`(`account_links:audit` — 머지·되돌리기·FK 무결성), `lib/tasks/seasons.rake`(`seasons:reconcile` — 시즌합 불변식·counter parity). `config/recurring.yml` 야간 점검(선택).

---

## 3. 수용 기준 (관측 가능)
- **FK 무결성**: 머지·reverse 직후 `PRAGMA foreign_key_check` **0행**.
- **테이블별 count parity**: `after(survivor) == before(survivor) + before(placeholder) − dropped_duplicates`. 조용한 FK(`quiz_contributions` cascade·`recommendation_imports` nullify) count 보존.
- **counter parity(표준/커스텀 구분)**: 표준 5종 `reset_counters` 후 저장값 == 연관 count(예 `book_intro.votes_count == book_intro.book_intro_votes.count`); **cheers는 `report.cheers_count == report.board_post.cheers.count`**(naive `report.cheers.count` 아님 — report에 직접 cheers 연관 없음).
- **active_monster 유효성**: 머지 후 `survivor.active_monster_id`는 pre-merge OLD 값 유지(in-place 승격으로 id 불변), 삭제행 미참조.
- **reverse 왕복**: 가역 필드 복원 + `foreign_key_check` 0 + counter parity + 병합-후 활동 잔류.
- **랭킹**: 시즌 정렬(신규 0 출발·최고참 비독점), 레벨·진화·전당·미션 보상 무회귀, 2027-03 0 재출발.

## 4. 확장 테스트 (명명 경로)
- `test/models/season_score_test.rb`, `test/models/concerns/pointable_test.rb`(시즌 훅·spend 불변·임포트 미시딩).
- `test/services/accounts/merge_service_test.rb`: `PRAGMA foreign_key_check` 0; count parity; **counter parity(표준5 + cheers 커스텀)**; user_monsters **in-place 승격**(stage 보존·celebrated_at 보존·active_monster 불변); book_intros/sequels 이관으로 delete_all abort 없음; 조용한 FK 보존; 시즌 sum-and-delete; **조건부 claim 동시성**(선행 커밋 후 후행 0행 rollback); hide 미재평가; 가드 위반 롤백.
- `test/models/account_merge_test.rb` + `test/integration/admin_account_links_test.rb`: **reverse 순서 왕복**(신원 복원 선행으로 tuple 충돌 없음, 원 id 재사용/새 id 리매핑 분기, 활동 잔류, counter parity).
- `test/integration/account_links_test.rb`: preview→confirm(redirect·CSRF·turbo 미사용)→세션 스왑; **스로틀 green + linkauth IP 분리 + 계정축 공유 + store seam 주입**; 일회성/자기연동/플래그 게이트.
- `test/integration/teacher_account_links_test.rb`(owned_student!·크로스학급 403), `test/policies/account_link_policy_test.rb`, `test/services/ranking_board_test.rb`(시즌·grade·신규0·최고참 비독점), `test/integration/rankings_test.rb`(grade 탭·방송).
- E2E: 3년 체인·전학·연중 연동·2027-03 롤오버.

## 5. 엣지 케이스
전학(school_id 승계 + 시즌 스냅샷 안정), 연중 연동(NEW 현재 시즌행 생존자 이관), self-link(old==new/old.academic_year==current 거부), 3년 체인(최고참 생존 단조·일회성은 같은 소스 재사용만 차단), 신규 학생 랭킹(LEFT JOIN 0), 순환 FK·삭제 순서, `Season` 사문 방치. **MINOR(구현 중 반영)**: cheers 재집계는 `update_columns` 사용(제3자 report 검증·콜백 우회); user_monsters in-place 승격 시 NEW 행 `nickname` 소실(OLD 유지, 미관 — 문서화); reverse 새 id 발급 시 되돌린 계정 신규 로그인 필요.

## 6. CLAUDE.md 갱신 (실행 시, 마트료시카 규칙)
`db/CLAUDE.md`(마이그레이션 #39·#40, 테이블 42) · `app/models/CLAUDE.md`(season_score·account_merge·user 승계) · `app/models/concerns/CLAUDE.md`(pointable 시즌 훅) · `app/services/CLAUDE.md`(accounts/merge_service·ranking_board 시즌·grade) · `app/controllers/CLAUDE.md`(account_links·login_throttling concern·profiles) · `app/controllers/teacher/CLAUDE.md` · `app/controllers/admin/CLAUDE.md` · `app/policies/CLAUDE.md` · `app/views/CLAUDE.md` · `config/CLAUDE.md`(라우트·플래그) · `lib/tasks/CLAUDE.md` · `test/CLAUDE.md`.

---

## 7. ADR
- **Decision**: (A) 계정 연동 = OLD 생존자 방향 MERGE(NEW 흡수·삭제, 세션 스왑, 신원 승계); (B) 랭킹 시즌제 = `season_scores(academic_year, user_id, experience_earned)` 정수 학년도 키잉 + Pointable 3 초크포인트 원자 훅 + RankingBoard 현재 시즌 읽기(평생 카운터·레벨·전당 불변). 되돌리기 = 감사-스냅샷 시간창 역머지.
- **Drivers**: 데이터 이동·충돌 최소화 / 아동 안전·오남용 저항 / 게임 루프 무회귀.
- **Alternatives considered**: NEW 생존 방향(복사·충돌·로스터 원칙 위배로 기각); `Season` 모델 확장(미사용 복잡성으로 기각); 소프트락 undo(유니크·유령계정으로 기각), 하드삭제-only undo(회복불가로 기각); user_monsters 생존자-우선 dedup(진화 자산 소실로 기각 → in-place 승격 채택).
- **Why chosen**: 로스터가 classroom_id 파생이라 생존자 이동만으로 정합; 정수 학년도가 `current_academic_year`와 1:1로 견고; in-place 승격이 진화 자산·active_monster를 보존; 스냅샷 역머지가 아동 안전(되돌리기 창) 충족.
- **Consequences**: 순환 FK·유니크 tuple로 **삭제·갱신 순서 계약** 발생(테스트로 고정); dedup은 6개 counter_cache 우회 → **재계산 필수**(표준 5종 `reset_counters`, cheers 커스텀 `update_columns`); placeholder 삭제는 **raw `delete_all`만**; active_monster는 NEW쪽만 NULL + OLD 열등행 in-place 승격으로 보존; reverse!는 **이동행 매니페스트 + 시즌 스냅샷** 의존, dedup 삭제분 불가역, 병합-후 활동 잔류, 순서=신원복원→placeholder삽입; 동시성은 조건부 claim + consumed 부분유니크로 fail-closed; 모더레이션 hide 플래그는 병합으로 자동 토글 안 함(sticky); 시즌 도입이 연중이면 부분 시즌(읽기 플래그로 2027-03 통제).
- **Follow-ups**: 미사용 `Season` 정리; nation-grade 개인 보드; reverse 매니페스트 보존기간 정책; `ranking_seasons` on 타이밍(2027-03) 확정; recurring 야간 무결성 점검.

---

## 8. 남은 사용자 결정
1. **`ranking_seasons` on 타이밍**: 2027-03 학년도 경계(권장) vs 소규모 파일럿 즉시.
2. **데이터 이전 동의 정책**: 학년 넘는 병합에 학교/보호자 동의 게이트 필요 여부.
3. **되돌리기 창 길이**: 교사 14일(권장), 총괄 무제한 수용 여부.
