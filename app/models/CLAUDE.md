# app/models — ActiveRecord 모델 계층 (도메인 데이터·규칙의 단일 진실)

'책갈피' 플랫폼의 모든 영속 도메인 객체가 모인 곳입니다. 사용자·학교부터 독후감·AI 첨삭, 반려몬스터 도감, 게이미피케이션, 커뮤니티, 퀴즈, 도서관까지 서비스 전 영역의 데이터 구조·연관관계·검증·enum을 정의합니다. 포인트 적립→뱃지→진화로 이어지는 핵심 게임 루프는 `concerns/`의 mixin(Pointable·Leveling·Evolvable·Badgeable)이 `User`에 얹혀 구동됩니다. 5축 루브릭·성취기준 등 도메인 상수는 DB가 아니라 `ReadingDomain` concern에 상수로 고정됩니다.

## 파일

### 사용자·학교
- `user.rb` — 5개 role(student·teacher·school_admin·librarian·superadmin) enum + mode(normal·easy) enum. `has_secure_password`, school·classroom·active_monster 소속 + `has_many :game_plays`(게임 완료 원장 — `reading_stats.rb`가 몬스터 해금 지표로 집계). Pointable·Leveling·Evolvable·Badgeable 4개 concern 포함(게임 루프 주체). 임시 비밀번호 생성 클래스 메서드 제공. **로그인 표면 2분화용 `email` 컬럼**: 학생은 튜플(학교·학급·이름)로, 교직원(`staff?`=`!student?`)은 이메일로 로그인한다(sessions_controller). email 은 저장 전 `normalize_email`(앞뒤 공백 제거+소문자, 빈 값 NULL)로 정규화하고 **형식·유일성(대소문자 무관)만 검증**(presence 미강제 — 이메일 없는 계정 생성 자체는 허용, 로그인만 불가). 교사 가입(registrations)에서 이메일을 필수로 받는다.
- `school.rb` — 학교. classroom·user를 거느리며 neis_code 유일성 검증. `address`(NEIS 도로명주소 원본), `active`(가입/검색 노출), `data_source`(manual/sample/neis), `synced_at` 컬럼 보유. `active` scope와 활성 학교만 반환하는 `form_regions` 제공. 구 합성 17교 코드는 `LEGACY_SAMPLE_CODES`로 식별해 전량 동기화 시 비활성 보존한다.
- `classroom.rb` — 학급. teacher(User) 담임 + 학생·독후감 소속. 학급별 루브릭 가중치(`rubric_config` JSON)를 기본값 주입·조회.
- `current.rb` — `ActiveSupport::CurrentAttributes`. 요청 단위 user·classroom 저장, user→school 위임.
- `application_record.rb` — 전 모델의 추상 베이스(`primary_abstract_class`).

### 독후감·AI 첨삭
- `report.rb` — 독후감. RubricScorable 포함. input_mode(keyboard·wongoji·ocr)·ai_status(pending·processing·done·failed) enum, photo·drawing·audio 첨부(서버 매직바이트 재식별 검증), 5축 rubric/교사 조정 rubric 접근자, 고쳐쓰기(revision_of 자기참조)·diff 제공.

### 도서
- `book.rb` — 도서. category(recommended·classic·searched) enum, report와 연결(`has_many :reports, dependent: :nullify`). **DB FK `reports.book_id → books` 도 `on_delete: :nullify` 로 정합화**(Phase 6 #6) — 도서 삭제 시 독후감을 남기고 참조만 끊는다(raw delete 경로 포함). **`validates :isbn, uniqueness: { allow_blank: true }`** — DB 부분 유니크 인덱스(`index_books_on_isbn`, `WHERE isbn IS NOT NULL AND isbn != ''`, 마이그레이션 #19)와 짝을 이루는 **소프트 게이트**(폼 경로 중복 isbn 을 `RecordNotUnique` 500 대신 폼 에러로 강등; 인덱스는 동시성까지 막는 하드 백스톱). allow_blank 라 텍스트-only(공란 isbn) 도서는 인덱스 술어와 동일하게 제약 밖(다건 공존). **`genre`(string, nullable) 컬럼**(10개 장르)은 무API `Books::GenreInference` 추론 보강 대상이며, 네이버 등록 도서는 `BookEnrichmentJob`이 공란을 채운다(고전은 여전히 category enum 의 classic). `GRADE_BANDS` 상수(초등 1~2/3~4/5~6 표준 라벨) — 표시·필터 전용이며, 게임 밴드(g12·g34·g56)는 학생 학년에서 파생되므로 이 상수와 무관.
- `recommendation_import.rb` — 총괄관리자 추천도서 XLSX 업로드 이력. 파일명·SHA-256 digest·원본 제목·업로더·시각·권수와 active 상태를 보존하며 `.current`가 학생 홈 현재 목록의 단일 진실이다.
- `book_recommendation.rb` — 업로드 시점과 Book의 연결 원장. 분과·호수·출간일·원본 순서를 저장하고 import 안에서 book 유일성을 보장한다.

### 반려몬스터
- `monster_species.rb` — 도감 종 카탈로그(시드). element·rarity enum, 진화 라인(evolves_from 자기참조)×stage, `evolve_condition` JSON 규칙(허용 키 화이트리스트·JSON 검증). 도감 분모는 설계 라인 24 고정. `has_many :next_forms, dependent: :nullify` + **DB 자기참조 FK `evolves_from_id` 도 `on_delete: :nullify`**(Phase 6 #8) — 이전 폼 삭제 시 다음 폼의 참조만 끊는다. **`unlock_condition` JSON 컬럼**(자동 해금 규칙, `docs/monster_unlocks.md §5`)은 `evolve_condition`과 별개 컬럼이지만 같은 화이트리스트(`ALLOWED_CONDITION_KEYS`)·JSON 검증을 공유하며, 라인 단위 규칙이라 stage 1 폼에만 값이 있다(2·3단계는 nil).
- `user_monster.rb` — 학생 보유/발견 개체(라인당 1행, 제자리 진화). `evolvable?`는 `ReadingStats#meets?`로 조건 평가, `evolution_cost`는 현재 단계 points 조건을 비용으로 노출, `evolve!`는 조건부 갱신으로 중복 진화를 방지. **`pending_celebration` scope**(`celebrated_at IS NULL`, 부분 인덱스 지원)로 아직 발견 연출을 안 보여 준 개체를 드레인한다(연출 모달 표시 후 `celebrated_at` 마킹으로 재노출 차단).

### 게이미피케이션
- `badge.rb` — 뱃지 카탈로그(13종 시드). `KEYS` 상수로 조건 트리거(Badgeable concern이 소비).
- `user_badge.rb` — 학생 획득 뱃지. (user, badge) 유일성으로 중복 방지.
- `mission.rb` — 학급 단위 독서 미션(**menu_refactor 심화 재설계**: 기간·정량목표·자동배정·정확히-1회 포인트보상). `belongs_to :classroom`·`:created_by`(User, optional, on_delete nullify), `has_many :mission_goals/:mission_participations`(dependent: :destroy). **레거시 `book` 연관·`book_id` 컬럼은 PR6 에서 드롭**(특정 도서 목표는 후속 goal_type). **status enum**(draft/published/cancelled/archived, 정수 0~3). 검증: title(1..80)·start/end_date 필수·`end_date >= start_date`·`reward_points 0..reward_max_points`(상한=`AppSetting.get("mission_reward_max_points")` 무효 시 `DEFAULT_REWARD_MAX_POINTS=200`, `self.reward_max_points`가 단일 진실로 서버 재검증)·**발행 시 목표≥1**(`published_requires_goal`, Rewarder m6 가드와 짝). 날짜 상태는 DB에 중복 저장 않고 `scheduled?`/`active?`/`ended?`로 `Date.current` 기준 파생. **완료 판정 단일 진실은 `mission_participations.completed_at`**(PR2에서 `ReadingStats#missions` 전환). **`publish!`**(§10.2): draft→published 전환은 트랜잭션(검증=목표≥1), 학급 학생 자동 배정·즉시 평가·방송은 커밋 후 `Missions::AssignmentSync.on_publish`로 분리.
- `mission_goal.rb` — 미션의 정량 목표(미션당 goal_type 1개). `belongs_to :mission`, **goal_type enum**(approved_reports=0[승인 독후감 수]·game_plays=1[게임 완료 수]). 검증: goal_type presence + `uniqueness scope: :mission_id`(DB 유니크 `[mission_id, goal_type]`와 짝) + `target_count > 0`(DB CHECK `chk_mission_goals_target_count_positive`와 짝).
- `mission_participation.rb` — 학생별 미션 참여·완료·보상 원장(미션당 학생 1행). `belongs_to :mission·:user`. 검증: `user_id uniqueness scope: :mission_id`(DB 유니크 `[mission_id, user_id]`=정확히-1회 백스톱과 짝) + `reward_points_awarded >= 0`(DB CHECK와 짝). `completed_at`=완료(몬스터 지표), `rewarded_at`+`reward_points_awarded`=정확히-1회 보상 원장(PR3 Rewarder가 `WHERE rewarded_at IS NULL` 조건부 UPDATE로 선점). `User has_many :mission_participations`.
- `challenge.rb` — 전역/학교 챌린지. scope(global·school) enum.
- `purchase.rb` — 상점 구매 기록(user·shop_item).
- `shop_item.rb` — 상점 카탈로그(포인트 sink). category(food·evolution_stone·care·decoration·accessory) enum.
- `season.rb` — 랭킹 리셋 시즌. scope(global·school) enum.

### 커뮤니티
- `board_post.rb` — 우수작 게시판 글(report당 1개). hidden 숨김 스코프, 응원 수는 report 카운터 캐시로 위임.
- `cheer.rb` — 응원(👏). 게시물당 사용자 1인 1회.
- `sticker.rb` — 문장 스티커 동료평가. report 본문 위치에 붙는 이모지.
- `topic.rb` — 토론방. scope(classroom·school) enum으로 경계 구분, hidden 스코프.
- `forum_post.rb` — 토론 글. topic counter_cache, 좋아요는 forum_post_likes(1인 1좋아요)로 likes_count counter_cache.
- `forum_post_like.rb` — 토론 글 좋아요(👍). `(forum_post, user)` 유일성=**1인 1좋아요**(cheer 패턴), `forum_post.likes_count` counter_cache.

### 퀴즈
- `quiz.rb` — 독서 퀴즈. scope(classroom·global) enum, published 노출 통제, quiz_questions nested attributes. **온디맨드 콘텐츠축 캐시 메타(Phase 1)**: `content_axis`(mcq·matching·hint_reveal, 캐시·dedup 키) / `band`(g12·g34·g56) / `origin`(teacher·system, `scopes:false` — `Quiz.origins[:system]` 해시만 사용) / `generation_status`(ready·warming·failed) / `content_version` / `reported` enum·컬럼 / `reports_count`(신고 카운터 캐시). 표면은 저장하지 않음. 정수 매핑 고정(Phase 2b 부분 유니크 인덱스·point_award 상한이 의존).
- `quiz_question.rb` — 퀴즈 문항. `question_type`(mcq_single·mcq_multi·matching·hint_reveal) + `source`(manual·ai·offline) enum. mcq_single 은 choices+answer_index 하위호환, 다형 타입은 content(문항)/answer(정답)/explanation/difficulty. **첫 AR 검증**(question_type presence + 타입별 정답 유효성). `correct?`(mcq_single) 유지 + `score_for(response, hints_used:)`가 `Games::QuestionScorer`에 위임. **Phase 3 뷰 헬퍼**: `content_hash`(심볼/문자열 키 무관 indifferent 접근) 위에 `hints_list`(hint_reveal)·`match_lefts`/`match_rights`(matching) — 방금 build 된 행과 DB 재조회 행에서 뷰가 동일 동작. **폼 입력용 `answer_number`** 가상 접근자(1-based getter/setter; 저장은 0-based `answer_index` 그대로 — 교사·관리자 퀴즈 폼이 이를 통해 입력받는다).
- `quiz_attempt.rb` — 퀴즈 플레이 1회 기록. `awarded_delta`는 멱등 지급 델타(비영속 임시 속성). 콘텐츠축 상한(origin=system)·per-quiz 상한(origin=teacher) 조회의 근거 행(`Games::PointAward`). **Phase 3 §3.2b**: `hint_reveals`(JSON `{question_id => 공개 힌트 수}`) 컬럼 + `revealed_count(question)` — whoami 힌트 공개수를 **세션쿠키 아니라 서버(DB)**에 두어 위조·stale-cookie replay 를 차단하는 hint_reveal 채점의 단일 진실(C1).

### 게임 — 완료 원장(몬스터 해금 지표)
- `game_play.rb` — 게임 완료 활동 원장 1행(Phase 3B). `game_type` enum 5종(quiz·classic·vocab·whoami·book, 정수 매핑 고정) + `belongs_to :user`·`:book`(optional). **부분 유니크 인덱스 2개**로 일일 dedup(book 있는 플레이는 `(user, game_type, book, 일자)`, 없는 플레이는 `(user, game_type, 일자)` — SQLite 유니크 인덱스가 NULL 을 서로 구별해 단일 인덱스로는 book-less 재제출을 막지 못하기 때문). **`game_type` 신뢰 경계**: 퀴즈 4종(quiz/classic/vocab/whoami)은 같은 mcq 콘텐츠(Quiz 행)를 공유해 서버가 Quiz 행만으론 표면을 구분할 수 없어 **검증된 클라이언트 선언(`params[:game]`, 5값 allowlist)**을 신뢰한다(book 은 라우트가 서버에서 확정). `reading_stats.rb`의 `game_plays`/`distinct_games`/`game_books` 지표 소스.

### 게임 — 콘텐츠 신고(무게이트 롤아웃)
- `quiz_report.rb` — 온디맨드 게임 콘텐츠 신고(무게이트 롤아웃 안전장치). `(quiz, user)` 유일성=**1인 1신고**(cheer 패턴), `quiz.reports_count` counter_cache. 서로 다른 신고자가 `Games::ContentProvider::REPORT_HIDE_THRESHOLD`(2)명에 도달하면 자동 숨김+재생성, 접수는 신고자 학급 담임 대시보드 "신고된 게임 콘텐츠" 섹션으로 사후 검토(교사 알림).

### 게임 — 콘텐츠 신고(무게이트 롤아웃 안전장치)
- `quiz_report.rb` — 온디맨드 게임 콘텐츠 신고. 콘텐츠축 캐시 quiz 당 **1인 1신고**(`(quiz, user)` unique, cheer/vote 패턴) + `quizzes.reports_count`(counter_cache). 서로 다른 `Games::ContentProvider::REPORT_HIDE_THRESHOLD`(2)명 신고 시 자동 숨김+재생성, 접수는 신고자 학급 담임 대시보드 "신고된 콘텐츠" 섹션으로 사후 검토된다.

### 게임 — 책 소개 대결(소셜)
- `book_intro.rb` — 책 소개 대결 글(교육 다양성 5종의 소셜 도메인). `belongs_to :user·:book·:classroom`, `has_many :book_intro_votes, dependent: :destroy`. body presence + 길이(10..1000) 검증. scope `for_classroom(book, classroom)`·`ranked`(votes_count desc→created desc), `voted_by?(user)`. **경계 격리는 `BookIntroPolicy`가 학급 단위로 강제**(퀴즈 파이프라인 밖, Gemini/Quiz 미생성).
- `book_intro_vote.rb` — 책 소개 투표(👍). `belongs_to :book_intro, counter_cache: :votes_count` + `:user`. `(book_intro, user)` 유일성으로 **소개당 1인 1표**(cheer 패턴, RecordNotUnique rescue).

### 도서관
- `library_loan.rb` — 인기대출 레코드. source(csv·data4library) enum, school_id NULL이면 전국 집계.
- `library_event.rb` — 이달의 책·행사(사서가 학교 단위 등록, book 선택).

### 설정
- `app_setting.rb` — 전역 시스템 설정(key로 조회, value는 JSON). get/set/`feature_enabled?(flag, scope:)` 제공. API 키·시크릿류는 검증으로 저장 차단. **스코프형 기능 플래그(Phase 2b C3)**: `feature_enabled?`가 전역 kill switch + 학급/학교 스코프 오버라이드(`"<flag>:classroom:<id>"`/`":school:<id>"`, 학급 우선→학교)를 반영해 **한 학급 사고를 전교 off 없이 격리**하고 파일럿→확대 롤아웃을 지원한다. 전역 값 false=하드 kill(스코프 무시), 미설정=파일럿(기본 off), true=확대(기본 on). `on_demand_games` 가 온디맨드 게임 워밍의 전역 kill switch 키.

## 하위 폴더
- [`concerns/`](concerns/CLAUDE.md) — 모델에 mixin하는 도메인 concern 모듈(포인트·레벨·진화·뱃지·루브릭·독서도메인 상수).

## 패턴·규칙
- **게임 루프 트리거 연쇄**: `User#award_points`(Pointable) → `refresh_badges!`(Badgeable) + `check_evolution!`(Evolvable) + 랭킹 방송이 한 번에 이어진다. 새 적립 지점은 반드시 `award_points`를 경유할 것.
- **도메인 상수는 코드로 고정**: 5축 루브릭 키·성취기준·등급 포인트·AI 프롬프트는 DB가 아니라 `ReadingDomain`에 상수로 둔다(§13). 도감 분모(24)·뱃지 KEYS도 상수.
- **enum은 정수 백엔드**: 모든 enum은 정수 매핑(role·ai_status·element 등). DB에는 숫자가 저장된다.
- **경계 격리는 정책에서**: 모델은 소속(school_id·classroom_id)만 보유하고, 역할·학교 경계 인가는 `app/policies`가 담당한다.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
