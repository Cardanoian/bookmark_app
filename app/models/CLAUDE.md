# app/models — ActiveRecord 모델 계층 (도메인 데이터·규칙의 단일 진실)

'책갈피' 플랫폼의 모든 영속 도메인 객체가 모인 곳입니다. 사용자·학교부터 독후감·AI 첨삭, 반려몬스터 도감, 게이미피케이션, 커뮤니티, 퀴즈, 도서관까지 서비스 전 영역의 데이터 구조·연관관계·검증·enum을 정의합니다. 포인트 적립→뱃지→진화로 이어지는 핵심 게임 루프는 `concerns/`의 mixin(Pointable·Leveling·Evolvable·Badgeable)이 `User`에 얹혀 구동됩니다. 5축 루브릭·성취기준 등 도메인 상수는 DB가 아니라 `ReadingDomain` concern에 상수로 고정됩니다.

## 파일

### 사용자·학교
- `user.rb` — 5개 role(student·teacher·school_admin·librarian·superadmin) enum + mode(normal·easy) enum. `has_secure_password`, school·classroom·active_monster 소속 + `has_many :game_plays`(게임 완료 원장 — `reading_stats.rb`가 몬스터 해금 지표로 집계) + **`has_many :quiz_contributions, dependent: :destroy`**(학생 출제 기여, Phase 3 §4 — DB FK `on_delete: :cascade` 와 정합, pending 행은 작성자와 생사를 같이하되 승인·물질화된 풀 Quiz 는 system_user 소유의 독립 행이라 무관). Pointable·Leveling·Evolvable·Badgeable 4개 concern 포함(게임 루프 주체). 임시 비밀번호 생성 클래스 메서드 제공. **로그인 표면 2분화용 `email` 컬럼**: 학생은 튜플(학교·학급·이름)로, 교직원(`staff?`=`!student?`)은 이메일로 로그인한다(sessions_controller). email 은 저장 전 `normalize_email`(앞뒤 공백 제거+소문자, 빈 값 NULL)로 정규화하고 **형식·유일성(대소문자 무관)만 검증**(presence 미강제 — 이메일 없는 계정 생성 자체는 허용, 로그인만 불가). 교사 가입(registrations)에서 이메일을 필수로 받는다.
- `school.rb` — 학교. classroom·user를 거느리며 neis_code 유일성 검증. `address`(NEIS 도로명주소 원본), `active`(가입/검색 노출), `data_source`(manual/sample/neis), `synced_at` 컬럼 보유. `active` scope와 활성 학교만 반환하는 `form_regions` 제공. 구 합성 17교 코드는 `LEGACY_SAMPLE_CODES`로 식별해 전량 동기화 시 비활성 보존한다.
- `classroom.rb` — 학급. teacher(User) 담임 + 학생·독후감 소속. 학급별 루브릭 가중치(`rubric_config` JSON)를 기본값 주입·조회. **`academic_year`(학년도, 마이그레이션 #38)**: 같은 학교의 같은 학년·반을 학년도별로 구분(유니크 `[school_id, academic_year, grade, class_no]`, 검증 scope 도 academic_year 포함). **`self.current_academic_year`**(3월부터 새 학년도라 1·2월은 전년도, KST 명시 변환 — 로그인·개설 폼 기본값과 시드·모델 기본값의 단일 진실). `before_validation :apply_default_academic_year`(생성 시 미지정이면 현재 학년도 주입 — find_or_create_by! 등 명시값 우선). `label`("N학년 M반")은 회귀 방지로 불변, **`label_with_year`**("2026학년도 N학년 M반")는 교차 학년도 구분 화면 전용.
- `current.rb` — `ActiveSupport::CurrentAttributes`. 요청 단위 user·classroom 저장, user→school 위임.
- `application_record.rb` — 전 모델의 추상 베이스(`primary_abstract_class`).

### 독후감·AI 첨삭
- `report.rb` — 독후감. RubricScorable 포함. input_mode(keyboard·wongoji·ocr)·ai_status(pending·processing·done·failed) enum, photo·drawing·audio 첨부(서버 매직바이트 재식별 검증), 5축 rubric/교사 조정 rubric 접근자, 고쳐쓰기(revision_of 자기참조)·diff 제공. **`before_validation :normalize_book_title`**(`book_title.to_s.squish.presence`) — 자유입력 책 제목의 앞뒤·중복 공백을 정규화해 `StudentLibraryQuery` 레거시 그룹핑·내 서재 책별 독후감 필터(`reports?book_title=`)가 하나의 정규형으로 수렴하게 한다(정상 제목 불변, 기존 행은 백필 마이그레이션 #27로 정규화).

### 도서
- `book.rb` — 도서. category(recommended·classic·searched) enum, report와 연결(`has_many :reports, dependent: :nullify`). **`before_validation :upgrade_cover_url_to_https`**(선행 `http://`→`https://` 승격, 멱등·blank 무변경) — 표지는 페이지 이미지 하위리소스라 HTTPS 배포(force_ssl)에서 `http://` 로 저장되면 브라우저가 혼합 콘텐츠(Mixed Content)로 차단해 표지가 안 뜬다. 시드·검색·보강·관리자 입력 등 모든 쓰기 경로가 이 콜백을 경유해 재발을 원천 차단하고, 기존 행은 백필 마이그레이션 #29로 승격했다. **DB FK `reports.book_id → books` 도 `on_delete: :nullify` 로 정합화**(Phase 6 #6) — 도서 삭제 시 독후감을 남기고 참조만 끊는다(raw delete 경로 포함). **모든 Book은 유효한 ISBN 필수**: ISBN-10·하이픈 입력은 `Books::Isbn`으로 ISBN-13 숫자 13자리로 정규화하고 presence·유효성·uniqueness를 검증한다. DB도 `isbn NOT NULL` + 형식 CHECK + 전체 UNIQUE 인덱스로 우회·동시성 경로를 막는다(마이그레이션 #24). ISBN 없는 학생 자유입력은 Book을 만들지 않고 `Report#book_title`에만 보존한다. **`volume`(integer, nullable) 컬럼(도서 시리즈 접기, 마이그레이션 #36)**: 판본마다 ISBN이 다른 시리즈 별권의 권차. 단권·searched·권차없는 시리즈는 NULL. **`self.autocomplete_grouped(term, limit: 20)`**: 자동완성에서 같은 title+author 시리즈 별권을 대표 1행으로 접고 `series_count`(권수)를 가상 속성으로 함께 낸다(SQLite 윈도우 함수로 대표행=권차 오름차순[NULL 후순위]→id 선정, searched 제외). **`self.series_volumes(title, author)`**: 한 시리즈의 전 권을 권차 순으로 반환한다(드릴다운용, searched 제외). **`genre`(string, nullable) 컬럼**(10개 장르)은 무API `Books::GenreInference` 추론 보강 대상이며, 네이버 등록 도서는 `BookEnrichmentJob`이 공란을 채운다(고전은 여전히 category enum 의 classic). **`summary_checked_at`(datetime, nullable) 컬럼(게임 재구성 Phase 4 §1a)**: Gemini 줄거리 생성(`BookSummaryJob`/`Ai::BookSummaryService`)의 **비파생 LLM 판정 결과 캐시** — "Gemini 확인을 이미 시도함". summary 가 blank 인데 checked_at 이 있으면 = Gemini 가 모르는 책(환각 방지로 저장 안 함, 재확인 안 함). 무키 잡은 세팅하지 않아(키 생기면 재시도) 영구 무명 마킹을 피한다. **가용성 게이트(§2a)의 AI-적격 판정 `classic? || summary.present?` 소스**. `GRADE_BANDS` 상수(초등 1~2/3~4/5~6 표준 라벨) — 표시·필터 전용이며, 게임 밴드(g12·g34·g56)는 학생 학년에서 파생되므로 이 상수와 무관.
- `recommendation_import.rb` — 총괄관리자 추천도서 XLSX 업로드 이력. 파일명·SHA-256 digest·원본 제목·업로더·시각·권수와 active 상태를 보존하며 `.current`가 학생 홈 현재 목록의 단일 진실이다.
- `book_recommendation.rb` — 업로드 시점과 Book의 연결 원장. 분과·호수·출간일·원본 순서를 저장하고 import 안에서 book 유일성을 보장한다.

### 반려몬스터
- `monster_species.rb` — 도감 종 카탈로그(시드). element·rarity enum, 진화 라인(evolves_from 자기참조)×stage, `evolve_condition` JSON 규칙(허용 키 화이트리스트·JSON 검증). 도감 분모는 설계 라인 24 고정. `has_many :next_forms, dependent: :nullify` + **DB 자기참조 FK `evolves_from_id` 도 `on_delete: :nullify`**(Phase 6 #8) — 이전 폼 삭제 시 다음 폼의 참조만 끊는다. **`unlock_condition` JSON 컬럼**(자동 해금 규칙, `docs/monster_unlocks.md §5`)은 `evolve_condition`과 별개 컬럼이지만 같은 화이트리스트(`ALLOWED_CONDITION_KEYS`)·JSON 검증을 공유하며, 라인 단위 규칙이라 stage 1 폼에만 값이 있다(2·3단계는 nil).
- `user_monster.rb` — 학생 보유/발견 개체(라인당 1행, 제자리 진화). `evolvable?`는 `ReadingStats#meets?`로 조건 평가, `evolution_cost`는 현재 단계 points 조건을 비용으로 노출, `evolve!`는 조건부 갱신으로 중복 진화를 방지. **`pending_celebration` scope**(`celebrated_at IS NULL`, 부분 인덱스 지원)로 아직 발견 연출을 안 보여 준 개체를 드레인한다(연출 모달 표시 후 `celebrated_at` 마킹으로 재노출 차단).

### 게이미피케이션
- `badge.rb` — 뱃지 카탈로그(13종 시드). `KEYS` 상수로 조건 트리거(Badgeable concern이 소비).
- `user_badge.rb` — 학생 획득 뱃지. (user, badge) 유일성으로 중복 방지.
- `mission.rb` — 학급 단위 독서 미션(**menu_refactor 심화 재설계**: 기간·정량목표·자동배정·정확히-1회 포인트보상). `belongs_to :classroom`·`:created_by`(User, optional, on_delete nullify), `has_many :mission_goals/:mission_participations`(dependent: :destroy). **레거시 `book` 연관·`book_id` 컬럼은 PR6 에서 드롭**(특정 도서 목표는 후속 goal_type). **status enum**(draft/published/cancelled/archived, 정수 0~3). 검증: title(1..80)·start/end_date 필수·`end_date >= start_date`·`reward_points 0..reward_max_points`(상한=`AppSetting.get("mission_reward_max_points")` 무효 시 `DEFAULT_REWARD_MAX_POINTS=200`, `self.reward_max_points`가 단일 진실로 서버 재검증)·**발행 시 목표≥1**(`published_requires_goal`, Rewarder m6 가드와 짝). 날짜 상태는 DB에 중복 저장 않고 `scheduled?`/`active?`/`ended?`로 `Date.current` 기준 파생. **완료 판정 단일 진실은 `mission_participations.completed_at`**(PR2에서 `ReadingStats#missions` 전환). **`publish!`**(§10.2): draft→published 전환은 트랜잭션(검증=목표≥1), 학급 학생 자동 배정·즉시 평가·방송은 커밋 후 `Missions::AssignmentSync.on_publish`로 분리.
- `mission_goal.rb` — 미션의 정량 목표(미션당 goal_type 1개). `belongs_to :mission`, **`belongs_to :book, optional: true`(특정 도서 지정)**, **goal_type enum**(approved_reports=0[승인 독후감 수]·game_plays=1[게임 완료 수]). 검증: goal_type presence + `uniqueness scope: :mission_id`(DB 유니크 `[mission_id, goal_type]`와 짝) + `target_count > 0`(DB CHECK `chk_mission_goals_target_count_positive`와 짝). **`book_id`가 있으면 그 책의 독후감/게임만 인정**(ProgressCalculator 가 book_id 로 필터), **nil 이면 아무 책의 독서활동으로도 목표를 채운다**(기존 동작). 도서 삭제 시 참조만 끊는다(DB FK `on_delete: :nullify`).
- `mission_participation.rb` — 학생별 미션 참여·완료·보상 원장(미션당 학생 1행). `belongs_to :mission·:user`. 검증: `user_id uniqueness scope: :mission_id`(DB 유니크 `[mission_id, user_id]`=정확히-1회 백스톱과 짝) + `reward_points_awarded >= 0`(DB CHECK와 짝). `completed_at`=완료(몬스터 지표), `rewarded_at`+`reward_points_awarded`=정확히-1회 보상 원장(PR3 Rewarder가 `WHERE rewarded_at IS NULL` 조건부 UPDATE로 선점). `User has_many :mission_participations`.
- `challenge.rb` — 전역/학교 챌린지. scope(global·school) enum.
- `season.rb` — (사문·미사용) 랭킹 리셋 시즌. scope(global·school) enum. **시즌제 랭킹은 이 모델이 아니라 `season_score.rb`(academic_year 정수 키잉)로 구현**한다(account_linking_seasons_plan §1.3(b) — Season 모델 확장은 복잡성으로 기각, 테이블은 방치).
- `season_score.rb` — **랭킹 시즌제 점수(account_linking_seasons_plan §Phase 0)**. 학년도(`academic_year`)별 학생 1행으로 그 학년도에 적립한 `experience_earned`·`points_earned`만 담는다(평생 `users.experience/points`와 분리 → 매 학년도 0 재출발, 랭킹의 단일 진실). `belongs_to :user`, `validates academic_year/user_id presence`·`experience_earned/points_earned >= 0`, `scope :for_year`. **증감은 Pointable 의 raw SQLite upsert(ON CONFLICT(academic_year,user_id))로만** 이뤄지고(모델 쓰기 API 없음), 스냅샷 3컬럼(school_id/classroom_id/grade)은 **감사·과거 시즌 재현 전용**이라 랭킹 그룹핑에는 쓰지 않는다(RankingBoard 는 현재 소속 users.classroom_id/school_id 로 group). 유니크 `[academic_year, user_id]`(`index_season_scores_identity`) 단 1개 + FK `user_id → users on_delete: :cascade`.

### 커뮤니티
- `board_post.rb` — 우수작 게시판 글(report당 1개). hidden 숨김 스코프, 응원 수는 report 카운터 캐시로 위임.
- `cheer.rb` — 응원(👏). 게시물당 사용자 1인 1회.
- `sticker.rb` — 문장 스티커 동료평가. report 본문 위치에 붙는 이모지.
- `topic.rb` — 토론방. scope(classroom·school) enum으로 경계 구분, hidden 스코프, `hidden_by`(숨김 귀속). book 을 걸면 **책 앵커드 독서 토론**(독서활동 화면 진입점). **검증(reading_discussion)**: 제목 길이(`TITLE_LENGTH` 2..60)·금칙어(`Moderation::TextDenylist::FORUM`)·**scope_boundary_present**(classroom 스코프면 classroom_id, school 스코프면 school_id 필수 — 교사 개설 시 학급 미확정으로 인한 **고아 토픽** 저장 차단).
- `forum_post.rb` — 토론 글. topic counter_cache(forum_posts_count), 좋아요는 forum_post_likes(1인 1좋아요)로 likes_count counter_cache, 신고는 forum_post_reports(1인 1신고)로 **reports_count** counter_cache, `hidden_by`(숨김 귀속). **검증(reading_discussion)**: text 길이(`TEXT_LENGTH` 2..500)·금칙어(FORUM 리스트). `reported_by?(user)`.
- `forum_post_like.rb` — 토론 글 좋아요(👍). `(forum_post, user)` 유일성=**1인 1좋아요**(cheer 패턴), `forum_post.likes_count` counter_cache.
- `forum_post_report.rb` — 토론 글 신고(reading_discussion). `(forum_post, user)` 유일성=**1인 1신고**(quiz_report 패턴), `forum_post.reports_count` counter_cache, `reason`(nullable). **자동 숨김 없음**(또래 저작물 집단신고 괴롭힘 방지) — 접수는 **저자 학급 담임** 대시보드 "신고된 토론 글" 사후 검토 신호로만 쓰이고, 실제 숨김은 담임(`Teacher::ForumModerations`)·총괄(`Admin::Moderation`)의 수동 판단.

### 퀴즈
- `quiz.rb` — 독서 퀴즈. scope(classroom·global) enum, published 노출 통제, quiz_questions nested attributes. **온디맨드 콘텐츠축 캐시 메타(Phase 1)**: `content_axis`(mcq·matching·hint_reveal, 캐시·dedup 키 — 게임 재구성 Phase 1 에서 **matching 생성 경로는 제거됐으나 enum 값은 재배열 방지·과거 기록차 휴면 보존**) / `band`(g12·g34·g56) / `origin`(teacher·system, `scopes:false` — `Quiz.origins[:system]` 해시만 사용) / `generation_status`(ready·warming·failed) / `content_version` / `reported` enum·컬럼 / `reports_count`(신고 카운터 캐시). 표면은 저장하지 않음. 정수 매핑 고정(Phase 2b 부분 유니크 인덱스·point_award 상한이 의존).
- `quiz_question.rb` — 퀴즈 문항. `question_type`(mcq_single·mcq_multi·matching·hint_reveal) + `source`(manual·ai·offline·**contributed**[학생 기여 승인, Phase 3 §4 additive — 정수 3, 재배열 금지]·**curated**[시드 큐레이션 문항, Stage 2 additive — 정수 4, 재배열 금지 — `db/seeds/book_quizzes.yml` 검수 문항의 물질화]) enum. mcq_single 은 choices+answer_index 하위호환, 다형 타입은 content(문항)/answer(정답)/explanation/difficulty. **첫 AR 검증**(question_type presence + 타입별 정답 유효성). `correct?`(mcq_single) 유지 + `score_for(response, hints_used:)`가 `Games::QuestionScorer`에 위임. **Phase 3 뷰 헬퍼**: `content_hash`(심볼/문자열 키 무관 indifferent 접근) 위에 `hints_list`(hint_reveal)·`match_lefts`/`match_rights`(matching) — 방금 build 된 행과 DB 재조회 행에서 뷰가 동일 동작. **폼 입력용 `answer_number`** 가상 접근자(1-based getter/setter; 저장은 0-based `answer_index` 그대로 — 교사·관리자 퀴즈 폼이 이를 통해 입력받는다).
- `quiz_attempt.rb` — 퀴즈 플레이 1회 기록. `awarded_delta`는 멱등 지급 델타(비영속 임시 속성). 콘텐츠축 상한(origin=system)·per-quiz 상한(origin=teacher) 조회의 근거 행(`Games::PointAward`). **Phase 3 §3.2b**: `hint_reveals`(JSON `{question_id => 공개 힌트 수}`) 컬럼 + `revealed_count(question)` — whoami 힌트 공개수를 **세션쿠키 아니라 서버(DB)**에 두어 위조·stale-cookie replay 를 차단하는 hint_reveal 채점의 단일 진실(C1).

### 퀴즈 — 큐레이션 게임 문항(Stage 2)
- `curated_quiz.rb` — **큐레이션 게임 문항(Stage 2)**. `belongs_to :book` + `content_axis` enum(mcq:0/hint_reveal:1 — **이 모델 전용 정수 매핑, Quiz enum 과 무관** — `Games::CuratedContent` 는 항상 심볼/문자열명으로 넘긴다)·`payload` JSON(그 축의 문항 배열, `db/seeds/book_quizzes.yml` 원본 형태). 검증: `payload` presence + `content_axis` uniqueness scope: `book_id`(DB 유니크 `[book_id, content_axis]`·도서 삭제 cascade 와 짝). `books:seed_quizzes` 가 물질화하고 `Games::CuratedContent.set_for` 가 균일 문항 해시로 변환해 `Games::ContentProvider` 가 큐레이션 우선 서빙(source=curated)·워밍 억제·가용성 게이트로 소비한다.

### 퀴즈 — 학생 출제 기여(전국 공유 문제은행 UGC)
- `quiz_contribution.rb` — **학생 출제 기여(게임 재구성 Phase 3 §4)**. `belongs_to :user`(작성 학생)·`:book`·`:classroom`·`:reviewed_by`(교사, optional). `content_axis` enum(mcq/hint_reveal — 이 모델 전용 정수 매핑, Quiz 정수 의존 없음: 물질화 때 심볼명으로 넘김)·`band`(g12/g34/g56)·`status`(pending:0/approved:1/rejected:2, 기본 pending)·**`payload` JSON**(mcq={prompt,choices[4],answer_index,explanation} / hint_reveal={answer,hints[≥2],explanation}). 검증: **축별 페이로드 유효성**(mcq 보기4·정답인덱스 범위, hint_reveal 정답+힌트≥2) + 금칙어(`Moderation::TextDenylist::QUIZ`). 승인 시 `Games::ContributionPublisher`가 system·global·band 풀 퀴즈로 물질화(전국 편입). Quiz/풀 밖의 pending 행이라 승인 전까지 아무에게도 안 보인다. `payload_hash`(indifferent 접근).

### 게임 — 완료 원장(몬스터 해금 지표)
- `game_play.rb` — 게임 완료 활동 원장 1행(Phase 3B). `game_type` enum(quiz:0·classic:1·whoami:3·book:4·**sequel:5**, **정수 매핑 고정**) + `belongs_to :user`·`:book`(optional). **게임 재구성 Phase 1**: vocab(2) hard-delete(키 제거, **정수 2 gap 유지·재넘버링 없음**), classic(1) soft-deprecate(값·과거 기록 보존, 새 표면 없음). **Phase 2**: sequel(5) additive 추가 → **활성 4종=quiz·whoami·book·sequel**(sequel 은 book 처럼 book_id 있는 플레이라 기존 부분 유니크 인덱스로 dedup). **부분 유니크 인덱스 2개**로 일일 dedup(book 있는 플레이는 `(user, game_type, book, 일자)`, 없는 플레이는 `(user, game_type, 일자)` — SQLite 유니크 인덱스가 NULL 을 서로 구별해 단일 인덱스로는 book-less 재제출을 막지 못하기 때문). **`game_type` 신뢰 경계**: 퀴즈 표면(quiz/whoami)은 서버가 Quiz 행만으론 표면을 구분할 수 없어 **검증된 클라이언트 선언(`params[:game]`, `game_types` allowlist)**을 신뢰한다(book 은 라우트가 서버에서 확정, vocab 은 enum 에서 빠져 자동 거부). `reading_stats.rb`의 `game_plays`/`distinct_games`/`game_books` 지표 소스.

### 게임 — 콘텐츠 신고(무게이트 롤아웃)
- `quiz_report.rb` — 온디맨드 게임 콘텐츠 신고(무게이트 롤아웃 안전장치). `(quiz, user)` 유일성=**1인 1신고**(cheer 패턴), `quiz.reports_count` counter_cache. 서로 다른 신고자가 `Games::ContentProvider::REPORT_HIDE_THRESHOLD`(2)명에 도달하면 자동 숨김+재생성, 접수는 신고자 학급 담임 대시보드 "신고된 게임 콘텐츠" 섹션으로 사후 검토(교사 알림).

### 게임 — 콘텐츠 신고(무게이트 롤아웃 안전장치)
- `quiz_report.rb` — 온디맨드 게임 콘텐츠 신고. 콘텐츠축 캐시 quiz 당 **1인 1신고**(`(quiz, user)` unique, cheer/vote 패턴) + `quizzes.reports_count`(counter_cache). 서로 다른 `Games::ContentProvider::REPORT_HIDE_THRESHOLD`(2)명 신고 시 자동 숨김+재생성, 접수는 신고자 학급 담임 대시보드 "신고된 콘텐츠" 섹션으로 사후 검토된다.

### 게임 — 책 소개 대결·뒷이야기 이어쓰기(소셜)
- `book_intro.rb` — 책 소개 대결 글(교육 다양성 5종의 소셜 도메인). `belongs_to :user·:book·:classroom`, `has_many :book_intro_votes, dependent: :destroy`. body presence + 길이(10..1000) 검증. scope `for_classroom(book, classroom)`·`ranked`(votes_count desc→created desc), `voted_by?(user)`. **경계 격리는 `BookIntroPolicy`가 학급 단위로 강제**(퀴즈 파이프라인 밖, Gemini/Quiz 미생성).
- `book_intro_vote.rb` — 책 소개 투표(👍). `belongs_to :book_intro, counter_cache: :votes_count` + `:user`. `(book_intro, user)` 유일성으로 **소개당 1인 1표**(cheer 패턴, RecordNotUnique rescue).
- `book_sequel.rb` — 뒷이야기 이어쓰기 글(게임 재구성 Phase 2의 창작 소셜 도메인, BookIntro 미러). `belongs_to :user·:book·:classroom`, `has_many :book_sequel_votes, dependent: :destroy`. body presence + 길이(**10..2000** — 이야기라 intro보다 김) 검증. scope `for_classroom`·`ranked`, `voted_by?`. **`ai_status` enum(pending·processing·done·failed, Report 미러)** + `ai_comment` — 제출 시 `SequelFeedbackJob`이 학생 글을 평가한 격려형 AI 코멘트를 비동기로 단다(정직한 AI: 책 아닌 학생 글 평가라 환각 없음). **경계 격리는 `BookSequelPolicy`가 학급 단위로 강제**. 콘텐츠 소스가 학생 상상이라 모든 책에서 항상 가능.
- `book_sequel_vote.rb` — 뒷이야기 공감(👍). `belongs_to :book_sequel, counter_cache: :votes_count` + `:user`. `(book_sequel, user)` 유일성으로 **뒷이야기당 1인 1표**(cheer 패턴, RecordNotUnique rescue).

### 도서관
- `library_loan.rb` — 인기대출 레코드. source(csv·data4library) enum, school_id NULL이면 전국 집계.
- `library_event.rb` — 이달의 책·행사(사서가 학교 단위 등록, book 선택).

### 설정
- `app_setting.rb` — 전역 시스템 설정(key로 조회, value는 JSON). get/set/`feature_enabled?(flag, scope:, default:)` 제공. API 키·시크릿류는 검증으로 저장 차단. **스코프형 기능 플래그(Phase 2b C3)**: `feature_enabled?`가 전역 kill switch + 학급/학교 스코프 오버라이드(`"<flag>:classroom:<id>"`/`":school:<id>"`, 학급 우선→학교)를 반영해 **한 학급 사고를 전교 off 없이 격리**하고 파일럿→확대 롤아웃을 지원한다. 전역 값 false=하드 kill(스코프 무시), true=확대(기본 on). **미설정(nil) 시 기본값은 `default:` 인자**(하위호환 default: false=파일럿 기본 off — `on_demand_games`; default: true=확대 기본 on — `reading_discussion`, 안전 스택 동반 출하). 하드 kill·스코프 오버라이드는 default 와 무관하게 항상 우선. `on_demand_games`(온디맨드 게임)·`reading_discussion`(독서 토론)이 kill switch 키.

## 하위 폴더
- [`concerns/`](concerns/CLAUDE.md) — 모델에 mixin하는 도메인 concern 모듈(포인트·레벨·진화·뱃지·루브릭·독서도메인 상수).

## 패턴·규칙
- **게임 루프 트리거 연쇄**: `User#award_points`(Pointable) → `refresh_badges!`(Badgeable) + `check_evolution!`(Evolvable) + 랭킹 방송이 한 번에 이어진다. 새 적립 지점은 반드시 `award_points`를 경유할 것.
- **도메인 상수는 코드로 고정**: 5축 루브릭 키·성취기준·등급 포인트·AI 프롬프트는 DB가 아니라 `ReadingDomain`에 상수로 둔다(§13). 도감 분모(24)·뱃지 KEYS도 상수.
- **enum은 정수 백엔드**: 모든 enum은 정수 매핑(role·ai_status·element 등). DB에는 숫자가 저장된다.
- **경계 격리는 정책에서**: 모델은 소속(school_id·classroom_id)만 보유하고, 역할·학교 경계 인가는 `app/policies`가 담당한다.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
