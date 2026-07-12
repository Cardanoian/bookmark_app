# 「책갈피」 Ruby on Rails 8 재구축 설계·구축 계획서

> **목적**: 프로토타입(`prototype/index.html` 바닐라 JS SPA + `localStorage` + Netlify Functions)이 검증한 도메인 가치를 유지하면서, **Rails 8 + SQLite3 + DigitalOcean** 실서버 아키텍처로 완전히 재구축하기 위한 착수 가능 수준의 설계 문서.
>
> 작성 기준: 프로토타입 v0.7 코드 분석(`연구/11_프로젝트_분석_보고서.md`) + 연구 문서 01~10 + 사용자 확정 의사결정.
> 최종 수정: 2026-07-04

---

## 목차

1. [배경과 목표](#1-배경과-목표)
2. [확정된 의사결정](#2-확정된-의사결정)
3. [기술 스택 (Rails 8)](#3-기술-스택-rails-8)
4. [Gemfile (gem 목록)](#4-gemfile-gem-목록)
5. [디렉터리 구조](#5-디렉터리-구조)
6. [데이터 모델 · DB 스키마](#6-데이터-모델--db-스키마)
7. [역할 체계 · 인가(Pundit)](#7-역할-체계--인가pundit)
8. [라우트 · 네임스페이스 맵](#8-라우트--네임스페이스-맵)
9. [OCR · AI · 외부 서비스 설계](#9-ocr--ai--외부-서비스-설계)
10. [실시간(Hotwire/Turbo) 설계](#10-실시간hotwireturbo-설계)
11. [프론트엔드 라이브러리·API 검토 (Keep/Remove/Change)](#11-프론트엔드-라이브러리api-검토-keepremovechange)
12. [디자인 시스템 (DESIGN.md)](#12-디자인-시스템-designmd)
13. [도메인 상수 (프로토타입 이식)](#13-도메인-상수-프로토타입-이식)
14. [배포 (DigitalOcean + Kamal 2)](#14-배포-digitalocean--kamal-2)
15. [보안 · 개인정보 · 규정](#15-보안--개인정보--규정)
16. [단계별 태스크 체크리스트](#16-단계별-태스크-체크리스트)
17. [검증 계획](#17-검증-계획)
18. [마이그레이션 노트 (프로토타입 → Rails 매핑)](#18-마이그레이션-노트-프로토타입--rails-매핑)

---

## 1. 배경과 목표

### 1.1 현재 프로토타입의 구조적 한계
- **데이터 영속성 없음** — 브라우저 `localStorage`(`chaek_db2`)에만 저장되어 기기·브라우저별로 격리. 교사↔학생 실시간 연동 불가. (원래 `연구/07_Firebase마이그레이션_설계.md`로 해결하려던 목표)
- **서버 부재** — OCR/LLM을 브라우저 또는 Netlify 서버리스로 우회. 학생 계정이 생성형 AI를 직접 호출하면 **연령제한 약관 위반 = 대회 등외**라는 규정을 구조적으로 강제하기 어려움.
- **단일 파일 유지보수 한계** — 2,354줄 인라인 HTML/CSS/JS, 3개 산출물 HTML 수동 동기화(`build.mjs`).

### 1.2 재구축 목표
| 목표 | 달성 수단 |
|------|-----------|
| 데이터 영속화·다기기 동기화 | Rails + SQLite3 서버 DB, **Hotwire Turbo Streams**(Firebase Realtime 대체) |
| AI 규정 준수 | 모든 OCR/LLM 호출을 **서버 서비스**로 이관, 키는 Rails credentials |
| 플랫폼 운영 | **총괄 관리자(superadmin)** 역할 신설 |
| 유지보수성 | MVC 분리, ViewComponent/partial, `DESIGN.md` 기반 Tailwind |
| 저비용 배포 | DigitalOcean 드로플릿 1대 + SQLite(Redis·외부 DB 불필요) |

### 1.3 유지해야 할 핵심 가치 (Must-Keep)
1. **AI 5축 "발전적" 첨삭** — 맞춤법 교정이 아니라 내용·구성·사고를 2022 개정 성취수준 기반으로 진단·확장.
2. **교사 Human-in-the-Loop** — AI 초안 → 교사 5축 ±조정 + 코멘트 + 최종 승인.
3. **손글씨 OCR** — 종이 독후감 사진 → 텍스트(서버 Gemini Vision), 학생이 결과 수정(사람 확인 루프).
4. **게이미피케이션** — 포인트·**반려 몬스터 도감/진화**(6단계 식물 성장·아바타 대체)·3단 랭킹·명예의 전당(**성장 기반** 랭킹).
5. **접근성(UDL)** — STT/TTS, 쉬운 말 모드.

---

## 2. 확정된 의사결정

| 항목 | 결정 | 근거/영향 |
|------|------|-----------|
| **프레임워크** | Ruby on Rails 8 | 서버 렌더 + Hotwire |
| **DB** | SQLite3 (dev·test·prod 공통) | Rails 8 프로덕션 SQLite 지원 |
| **배포** | DigitalOcean 드로플릿 + Kamal 2 | 퍼시스턴트 볼륨에 SQLite/스토리지 |
| **OCR** | **Gemini Vision 서버 호출만. Tesseract.js 완전 제거** | 키 없으면 사진 OCR 비활성(키보드·원고지만). AI 첨삭은 규칙기반 폴백 유지 |
| **총괄관리자** | 학교·사용자 관리 + 전역 콘텐츠 + 시스템 설정 + 전교 통합 통계 + 모더레이션 (전부) | 전역 네임스페이스 + Pundit |
| **외부 연동 유지** | 도서 검색(Kakao→Naver), Gemini AI 첨삭 | 서버 서비스로 이관 |
| **외부 연동 신규** | 정보나루 도서관 API(data4library.kr) | 실제 인기대출 집계 |
| **외부 연동 제거** | Daum 맞춤법 스크래퍼 | `spelling` 루브릭 축이 대체 |
| **UI** | Tailwind 새 디자인 + `DESIGN.md` 토큰 관리 | 기존 룩앤필에 얽매이지 않음 |
| **게이미피케이션 축** | **아바타·6단계 식물 성장 → 반려 몬스터 도감(수집형) + 진화** | 초등 동기부여↑, 진화 조건=독서 습관 유도 장치, 성장의 시각 표현을 몬스터로 통일 |

---

## 3. 기술 스택 (Rails 8)

| 레이어 | 채택 | 비고 |
|--------|------|------|
| 런타임 | Ruby 3.3+ (권장 3.4) | |
| 프레임워크 | Rails 8.0 | |
| DB | SQLite3 (primary + queue/cache/cable 다중 DB) | Redis 불필요 |
| 백그라운드 잡 | **Solid Queue** | OCR·AI 첨삭 비동기 |
| 캐시 | **Solid Cache** | |
| WebSocket/실시간 | **Solid Cable** + Turbo Streams | 교사↔학생 실시간 |
| 프론트 | **Hotwire** (Turbo Drive/Frames/Streams + Stimulus) | |
| 에셋 | **Propshaft** + **importmap-rails** | 번들러 불필요(무거운 JS 제거) |
| CSS | **tailwindcss-rails** (Tailwind v4) | `DESIGN.md` 토큰 |
| 파일 저장 | **Active Storage** | 사진·그림·오디오 |
| 인증 | `has_secure_password`(bcrypt) + 커스텀 SessionsController | 튜플 신원 |
| 인가 | **Pundit** | 5역할 정책 |
| 뷰 컴포넌트 | ViewComponent (선택) 또는 partial | |
| HTTP 클라이언트 | `Faraday` 또는 Net::HTTP | 외부 API |
| 테스트 | Minitest(기본) + Capybara + Cuprite(headless Chrome) | 시스템 테스트 |
| 배포 | **Kamal 2** + Thruster | Docker |
| 웹서버 | Puma | |

---

## 4. Gemfile (gem 목록)

```ruby
ruby "3.4.1"

# --- Core ---
gem "rails", "~> 8.0"
gem "sqlite3", ">= 2.1"
gem "puma", ">= 6.0"
gem "propshaft"

# --- Hotwire / Front ---
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"

# --- Rails 8 Solid adapters ---
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"

# --- Auth / Authz ---
gem "bcrypt", "~> 3.1.7"      # has_secure_password
gem "pundit"                  # 역할 인가

# --- 외부 API ---
gem "faraday"                 # Gemini / Kakao / Naver / 정보나루

# --- 파일/이미지 ---
gem "image_processing", "~> 1.2"   # Active Storage variant (표지 리사이즈 등)

# --- 배포 ---
gem "kamal", require: false
gem "thruster", require: false

# --- 부팅/최적화 ---
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri ]
  gem "brakeman", require: false          # 보안 정적분석
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "cuprite"                            # headless Chrome (selenium 대체)
end
```

> **주의**: Tesseract 관련 gem(`rtesseract` 등)은 **추가하지 않는다**(OCR은 Gemini만). Daum 맞춤법/`nokogiri` 스크래핑도 제거.

---

## 5. 디렉터리 구조

```
chaekgalpi/
├── app/
│   ├── controllers/
│   │   ├── application_controller.rb         # 인증·Pundit·Current 세팅
│   │   ├── sessions_controller.rb            # 로그인/로그아웃(튜플 신원)
│   │   ├── registrations_controller.rb       # 학생·교사 가입
│   │   ├── dashboard_controller.rb           # 로그인 후 역할별 라우팅
│   │   ├── reports_controller.rb             # 독후감 CRUD + revise
│   │   ├── ocr_controller.rb                 # 사진 업로드 → OCR 잡 트리거
│   │   ├── books_controller.rb               # 검색/카탈로그
│   │   ├── games/…                           # 독서게임 10종
│   │   ├── rankings_controller.rb
│   │   ├── board_posts_controller.rb / cheers_controller.rb
│   │   ├── topics_controller.rb / forum_posts_controller.rb
│   │   ├── monsters_controller.rb            # 몬스터 도감·진화(evolve)·대표설정·먹이
│   │   ├── shop_controller.rb / purchases_controller.rb  # 몬스터 케어/진화 아이템 상점
│   │   ├── learn_controller.rb               # 단계 학습 위저드
│   │   ├── teacher/                          # 담임 네임스페이스
│   │   │   ├── dashboard_controller.rb
│   │   │   ├── reviews_controller.rb         # 검토·승인·진위
│   │   │   ├── students_controller.rb
│   │   │   ├── missions_controller.rb
│   │   │   ├── quizzes_controller.rb
│   │   │   └── rubric_configs_controller.rb
│   │   ├── school_admin/                     # 교무관리자 네임스페이스
│   │   │   ├── stats_controller.rb
│   │   │   └── neis_controller.rb
│   │   ├── librarian/                        # 사서 네임스페이스
│   │   │   ├── dashboard_controller.rb
│   │   │   ├── events_controller.rb
│   │   │   └── loans_controller.rb           # 정보나루 API + CSV 업로드
│   │   └── admin/                            # 총괄관리자(superadmin) 네임스페이스
│   │       ├── schools_controller.rb
│   │       ├── users_controller.rb
│   │       ├── books_controller.rb           # 전역 콘텐츠
│   │       ├── quizzes_controller.rb
│   │       ├── moderation_controller.rb      # 게시판/토론 신고
│   │       ├── settings_controller.rb        # 기능 플래그
│   │       └── analytics_controller.rb       # 전교 통합 통계
│   │
│   ├── models/
│   │   ├── school.rb  classroom.rb  user.rb  report.rb  book.rb
│   │   ├── quiz.rb  quiz_question.rb  quiz_attempt.rb
│   │   ├── mission.rb  challenge.rb  season.rb
│   │   ├── board_post.rb  cheer.rb  sticker.rb
│   │   ├── topic.rb  forum_post.rb
│   │   ├── badge.rb  user_badge.rb
│   │   ├── shop_item.rb  purchase.rb
│   │   ├── monster_species.rb  user_monster.rb
│   │   ├── library_loan.rb  app_setting.rb
│   │   ├── current.rb                        # Current.user/classroom (ActiveSupport::CurrentAttributes)
│   │   └── concerns/
│   │       ├── pointable.rb  leveling.rb  evolvable.rb  badgeable.rb
│   │       └── rubric_scorable.rb            # A/B/C 산출 로직
│   │
│   ├── services/
│   │   ├── ai/
│   │   │   ├── gemini_client.rb              # generateContent 래퍼
│   │   │   ├── ocr_service.rb                # Vision OCR
│   │   │   ├── review_service.rb             # 5축 첨삭(LLM)
│   │   │   ├── rule_based_review.rb          # 규칙기반 폴백
│   │   │   ├── quiz_draft_service.rb
│   │   │   └── verify_service.rb             # 진위·표절
│   │   ├── books/search_service.rb           # Kakao→Naver
│   │   └── library/data4library_service.rb   # 정보나루
│   │
│   ├── jobs/
│   │   ├── ocr_job.rb
│   │   ├── ai_review_job.rb
│   │   └── book_cover_prefetch_job.rb
│   │
│   ├── policies/                             # Pundit
│   │   ├── application_policy.rb
│   │   ├── report_policy.rb  classroom_policy.rb
│   │   └── admin/…
│   │
│   ├── components/                           # ViewComponent(선택)
│   │   ├── radar_chart_component.rb          # 5축 방사형 SVG
│   │   ├── monster_component.rb              # 몬스터 표시(종·진화단계 이미지)
│   │   ├── dex_component.rb                  # 몬스터 도감 그리드
│   │   ├── podium_component.rb  evolution_roadmap_component.rb
│   │   └── book_card_component.rb
│   │
│   ├── javascript/controllers/               # Stimulus
│   │   ├── wongoji_controller.js             # 원고지 200칸 그리드
│   │   ├── speech_controller.js              # STT/TTS(Web Speech)
│   │   ├── recorder_controller.js            # 낭독 녹음(MediaRecorder)
│   │   ├── photo_upload_controller.js        # 사진 압축(Canvas) + 미리보기 + 돋보기
│   │   ├── growth_card_controller.js         # 성장 카드 PNG(Canvas)
│   │   ├── book_search_controller.js         # 자동완성 debounce
│   │   ├── dex_controller.js                 # 도감 필터·상세
│   │   └── monster_care_controller.js        # 먹이 주기·진화 연출
│   │
│   └── views/…                               # 역할별 레이아웃/화면
│
├── config/
│   ├── database.yml                          # primary + queue/cache/cable
│   ├── routes.rb
│   ├── deploy.yml                            # Kamal
│   ├── credentials.yml.enc                   # API 키
│   └── initializers/…
│
├── db/
│   ├── migrate/…
│   ├── schema.rb
│   └── seeds.rb                              # 6,331 학교 + 데모 학급 + 도메인 상수
│
├── lib/tasks/
│   └── schools.rake                          # schools.js → DB 변환·시드
│
├── storage/                                  # SQLite DB + Active Storage (볼륨 마운트)
├── DESIGN.md                                 # 디자인 토큰 메타데이터(신규)
├── RAILS_PLAN.md                             # 본 문서
└── prototype/                                # 참조용으로 보존(빌드에서 제외)
```

---

## 6. 데이터 모델 · DB 스키마

프로토타입 `db = { accounts, reports, challenge, season, shop, dls, quizzes, board, forum, topics, rubricCfg … }`를 관계형으로 정규화. JSON 컬럼은 SQLite `json` 타입(Rails `t.json`) 사용.

### 6.1 ER 개요

```
School 1─* Classroom 1─* User(student)         School 1─* User(school_admin, librarian)
Classroom 1─1 User(teacher)                     User(superadmin) — school_id NULL(전역)
User(student) 1─* Report *─1 Book
Report 1─* Sticker,  Report 1─1 BoardPost,  BoardPost 1─* Cheer
Classroom 1─* Mission,  (School|global) 1─* Challenge/Season
Book 1─* Quiz 1─* QuizQuestion,  User 1─* QuizAttempt
Classroom|School 1─* Topic 1─* ForumPost
User *─* Badge (UserBadge),  User *─* ShopItem (Purchase — 몬스터 케어/진화 아이템)
User 1─* UserMonster *─1 MonsterSpecies,  MonsterSpecies 1─1 MonsterSpecies(evolves_from 진화체인)
School 1─* LibraryLoan,  AppSetting(전역 key-value)
```

### 6.2 테이블 정의 (DDL 스케치)

> 모든 테이블에 `created_at`, `updated_at` 포함(생략 표기).

#### schools
| 컬럼 | 타입 | 제약 | 설명 |
|------|------|------|------|
| id | integer PK | | |
| neis_code | string | index, unique | NEIS 표준학교코드 |
| name | string | index | 학교명 |
| region | string | | 시도교육청 |
| gu | string | | 시군구 |
| office_code | string | | 교육청 코드 |

시드: `lib/tasks/schools.rake`가 `prototype/schools.js`(6,331교)를 파싱해 삽입. `name`에 검색 인덱스.

#### classrooms
| 컬럼 | 타입 | 제약 | 설명 |
|------|------|------|------|
| id | integer PK | | |
| school_id | integer FK→schools | index | |
| grade | integer | | 학년 |
| class_no | integer | | 반 |
| teacher_id | integer FK→users | nullable, index | 담임 |
| rubric_config | json | | `{weights:{content,emotion,life,structure,spelling}, emphasis, label}` |
| | | unique(school_id, grade, class_no) | |

프로토타입 `ckey`(schoolCode|grade|classNo)를 1급 모델로 승격. **교사는 여러 Classroom 담임 가능**(다학급 지원).

#### users
| 컬럼 | 타입 | 제약 | 설명 |
|------|------|------|------|
| id | integer PK | | |
| role | integer(enum) | default: student, index | student/teacher/school_admin/librarian/superadmin |
| school_id | integer FK | nullable(superadmin=NULL), index | |
| classroom_id | integer FK | nullable, index | 학생·교사 |
| name | string | not null | |
| password_digest | string | not null | bcrypt |
| points | integer | default: 0 | 학생 |
| mode | integer(enum) | default: normal | normal/easy(쉬운 말) |
| active_monster_id | integer FK→user_monsters | nullable | 대표(활성) 몬스터 |
| suspended | boolean | default: false | 총괄 정지 |
| | | unique(school_id, grade?, classroom_id, name) | 튜플 신원 |

로그인 신원 = (school, classroom, name) + password. 인덱스: `[school_id, classroom_id, name]`.

#### reports (독후감 — 가장 풍부한 레코드)
| 컬럼 | 타입 | 제약 | 설명 |
|------|------|------|------|
| id | integer PK | | |
| user_id | integer FK→users | index | 작성자 |
| classroom_id | integer FK | index | |
| book_id | integer FK→books | nullable, index | |
| book_title | string | | 검색 미연동 시 원문 |
| body | text | | 본문 |
| input_mode | integer(enum) | | keyboard/wongoji/ocr |
| rubric | json | | AI 5축 `{content,emotion,life,structure,spelling}` (0~5) |
| avg | real | | 5축 평균 |
| level | string(1) | index | A/B/C |
| teacher_rubric | json | nullable | 교사 조정 5축 |
| teacher_comment | text | nullable | |
| reviewed | boolean | default: false, index | 검토 완료 |
| reviewed_at | datetime | nullable | |
| shared | boolean | default: false | 우수작 공유 |
| cheers_count | integer | default: 0 | counter cache |
| challenge_id | integer FK | nullable | |
| mission_id | integer FK | nullable | |
| revision_of | integer FK→reports | nullable | 고쳐쓰기 원본 |
| prev_avg | real | nullable | 향상도 계산용 |
| improvement | real | nullable | 향상도 |
| similarity | real | nullable | 표절 의심(학급 내 최대 유사도) |
| ai_status | integer(enum) | default: pending | pending/processing/done/failed (비동기 잡 상태) |

Active Storage 첨부: `has_one_attached :photo`, `:drawing`, `:audio`.
인덱스: `[classroom_id, reviewed]`(교사 검토 큐), `[user_id, created_at]`.

#### books
| 컬럼 | 타입 | 설명 |
|------|------|------|
| id PK / title(index) / author / publisher / isbn(index) / cover_url / grade_band / category(enum: recommended/classic/searched) / summary(text) |

44 권장도서 + 고전 시드. 검색 결과는 `category: searched`로 upsert 캐시(프로토타입 `_bkc` localStorage 대체).

#### quizzes / quiz_questions / quiz_attempts
- **quizzes**: `book_id`, `classroom_id`(nullable — NULL이면 전역/총괄), `created_by`(FK users), `title`, `scope`(enum: classroom/global), `published`(bool).
- **quiz_questions**: `quiz_id FK`, `prompt`, `choices`(json 배열), `answer_index`(integer), `position`.
- **quiz_attempts**: `quiz_id FK`, `user_id FK`, `score`, `answers`(json), `played_at`. (게임 포인트 반영)

#### missions / challenges / seasons
- **missions**: `classroom_id FK`, `book_id`, `title`, `start_date`, `end_date`.
- **challenges**: `scope`(enum global/school), `school_id`(nullable), `book_id`, `title`, `start`, `end`.
- **seasons**: `scope`, `school_id`(nullable), `name`, `end_date`.

#### board_posts / cheers / stickers
- **board_posts**: `report_id FK`(unique), `hidden`(bool — 모더레이션), `hidden_by`(FK users nullable).
- **cheers**: `board_post_id FK`, `user_id FK`, unique(board_post_id, user_id). 👏 응원.
- **stickers**: `report_id FK`, `position`(integer), `emoji`, `label`, `by_user_id FK`. 문장 스티커 동료평가.

#### topics / forum_posts
- **topics**: `scope`(enum classroom/school), `classroom_id`/`school_id`(nullable), `book_id`, `title`, `hidden`(bool).
- **forum_posts**: `topic_id FK`, `user_id FK`, `text`, `likes_count`(default 0), `hidden`(bool).

#### badges / user_badges
- **badges**: `key`(unique, 예: first/three/ten/levelA/tripleA/reviser/grower/challenger/ocr/first_evolve/dex_half/dex_complete/final_form), `name`, `icon`, `condition_desc`. (13종 카탈로그 시드)
- **user_badges**: `user_id FK`, `badge_id FK`, `earned_at`, unique(user_id, badge_id).

#### shop_items / purchases (아바타 상점 → 몬스터 케어/진화 아이템으로 피벗)
- **shop_items**: `category`(enum food/evolution_stone/care/decoration/accessory), `name`, `icon`, `cost`(integer), `image_key`, `effect`(json — 예: `{restores:"hunger", evolve_boost:true, applies_element:"story"}`), `consumable`(bool).
- **purchases**: `user_id FK`, `shop_item_id FK`, `quantity`(integer, default 1 — 소모품 재고), `bought_at`. 소모품(먹이·돌)은 수량 증가, 영구 장식은 unique(user_id, shop_item_id).

#### monster_species (반려 몬스터 도감 카탈로그 — 시드)
| 컬럼 | 타입 | 제약 | 설명 |
|------|------|------|------|
| id | integer PK | | |
| dex_no | integer | index | 도감 번호(진화 라인 식별) |
| stage | integer | | 진화 단계 1(기본형)/2(성장형)/3(완전형) |
| key | string | unique | 슬러그 |
| name | string | | 이름 |
| element | integer(enum) | | story/knowledge/emotion/adventure/nature/imagination (속성·장르 친화) |
| rarity | integer(enum) | | common/rare/epic (해금 순서·연출) |
| evolves_from_id | integer FK→monster_species | nullable, index | 이전 단계 폼 |
| evolve_condition | json | | 다음 단계 진화 조건(§13.5) 예: `{points:250, distinct_genres:3, a_grades:2, classics:1, streak_days:5, badge:"reviser"}` |
| image_key | string | | AI 생성 애니메이션 WebP 에셋 키 |
| description | text | | 도감 설명 |

- ~20~30 진화 라인 × 3단계 = 60~90 폼. **초기엔 스타터 포함 12라인만 시드** 후 확장(에셋 물량 관리).
- 진화 조건은 포인트 임계 **+ 독서 행동 조건 조합**(단순 레벨 게이트 지양). 라인마다 성격이 달라 서로 다른 독서 습관을 유도(§13.5).

#### user_monsters (학생 보유/발견 몬스터 = 도감 수집 상태)
| 컬럼 | 타입 | 제약 | 설명 |
|------|------|------|------|
| id | integer PK | | |
| user_id | integer FK→users | index | |
| dex_no | integer | index | 진화 라인 |
| monster_species_id | integer FK→monster_species | | 현재 폼(진화 시 갱신) |
| nickname | string | nullable | 학생 지정 별명 |
| obtained_at | datetime | | 발견 시각 |
| evolved_at | datetime | nullable | 최근 진화 시각 |
| care | json | | 케어 상태 `{hunger, happiness, last_fed_at}` (선택) |
| | | unique(user_id, dex_no) | 라인당 1개(제자리 진화) |

- 도감 완성도 = `보유 dex_no 수 / 전체 라인 수`.
- **획득은 노력 기반(가챠 금지)**: 첫 스타터는 3종 중 선택, 이후 트레이너 레벨업·챌린지·뱃지 달성 등 마일스톤마다 새 몬스터 "발견"(알 부화 연출). 랜덤 뽑기·유료 요소 없음(대회 공정성·아동 사행성 방지).

#### library_loans
- `school_id FK`(nullable — 전국 집계는 NULL), `book_title`, `isbn`(nullable), `count`(integer), `source`(enum: csv/data4library), `period`(string 예: "2026-06").

#### app_settings (총괄 시스템 설정)
- `key`(unique), `value`(json), `description`. 예: `feature_flags`, `default_rubric_weights`, `seasonal_banner`.
- ※ **API 키는 여기 저장 금지** — Rails credentials/ENV.

### 6.3 enum 정의 (Ruby)
```ruby
# User
enum :role, { student: 0, teacher: 1, school_admin: 2, librarian: 3, superadmin: 4 }
enum :mode, { normal: 0, easy: 1 }
# Report
enum :input_mode, { keyboard: 0, wongoji: 1, ocr: 2 }
enum :ai_status,  { pending: 0, processing: 1, done: 2, failed: 3 }
# ShopItem
enum :category, { food: 0, evolution_stone: 1, care: 2, decoration: 3, accessory: 4 }
# MonsterSpecies
enum :element, { story: 0, knowledge: 1, emotion: 2, adventure: 3, nature: 4, imagination: 5 }
enum :rarity,  { common: 0, rare: 1, epic: 2 }
```

---

## 7. 역할 체계 · 인가(Pundit)

### 7.1 5역할 요약
| 역할(enum) | 한글 | scope | 셀프가입 | 핵심 권한 |
|------------|------|-------|---------|-----------|
| `student` | 학생 | 본인 | O | 독후감 작성·고쳐쓰기, 게임, 상점, 랭킹, 우수작/토론 참여 |
| `teacher` | 담임교사 | 학급(다학급) | O | 검토·5축 조정·승인, 학생 관리, 미션·퀴즈 출제, 루브릭 설정, PDF/CSV |
| `school_admin` | 교무관리자 | 학교 | X(발급) | 전교 통계, NEIS 생기부 자동요약 |
| `librarian` | 도서관 담당 | 학교 | X(발급) | 도서관 대시보드, 인기대출(정보나루/CSV), 이달의 책·행사 |
| `superadmin` | **총괄관리자(신규)** | **전역** | X(시드) | 학교·사용자 관리, 전역 콘텐츠, 시스템 설정, 전교 통합 통계, 모더레이션 |

### 7.2 Pundit 정책 개요
- **ReportPolicy**: `create?` = student && 본인. `update?` = 작성자(본인 글) 또는 담당 교사. `review?/approve?` = 학급 담임 교사. `destroy?` = 작성자 또는 담임 또는 superadmin.
- **ClassroomPolicy**: 학생/교사는 자기 학급만. school_admin/librarian은 자기 학교 읽기. superadmin 전역.
- **Admin::* 정책**: `superadmin`만 통과. `before_action`에서 `authorize [:admin, record]`.
- **Scope**: `policy_scope`로 목록 자동 필터(예: 교사는 자기 학급 reports만).

```ruby
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  before_action :require_login
  rescue_from Pundit::NotAuthorizedError, with: -> { head :forbidden }
end
```

### 7.3 총괄관리자 신설 상세
- 전용 네임스페이스 `/admin`(=superadmin). 일반 school_admin(교무관리자)과 **명확히 구분**(코드명 `school_admin` vs `superadmin`).
- 기능:
  1. **학교·사용자 관리** — 학교 등록/승인, 전 계정 검색·역할 부여·정지(`suspended`)·비밀번호 초기화, 학급 생성/이동.
  2. **전역 콘텐츠** — 권장도서·고전·전역 퀴즈·뱃지·상점 아이템·**몬스터 도감(종·진화 규칙)** CRUD.
  3. **시스템 설정** — `app_settings` 기능 플래그, 기본 루브릭 가중치, 데모 시드 재생성.
  4. **전교 통합 통계** — 전 학교 참여율·5축 평균·전국 랭킹 원자료, CSV 내보내기.
  5. **모더레이션** — `board_posts.hidden`, `forum_posts.hidden`, 신고 처리.

---

## 8. 라우트 · 네임스페이스 맵

```ruby
Rails.application.routes.draw do
  root "dashboard#show"                      # 로그인 상태·역할에 따라 분기

  # 인증 (튜플 신원)
  resource :session, only: [:new, :create, :destroy]
  resources :registrations, only: [:new, :create]     # 학생·교사 가입
  get  "schools/search", to: "schools#search"          # 로그인 자동완성(JSON)

  # 학생 영역
  resources :reports do
    member   { post :revise; post :share }
    resource :review, only: [:show], module: :reports  # AI 첨삭 결과(Turbo Frame)
  end
  resource  :ocr, only: [:create]            # 사진 업로드 → OcrJob
  resources :books, only: [:index, :show] do
    collection { get :search }               # Kakao/Naver 자동완성(JSON)
  end
  resources :rankings, only: [:index]        # rkTab: class/school/nation/challenge/hall
  namespace :games do                        # 독서게임 5종(교육 다양성 우선 축소)
    resources :classic, :quiz, :vocab, :whoami, only: [:show]
    # book(책 소개 대결)은 소셜 도메인 — 자체 라우트(play/create/vote/unvote)
  end
  resources :board_posts, only: [:index, :show] do
    resources :cheers, only: [:create, :destroy]
    resources :stickers, only: [:create]
  end
  resources :topics, only: [:index, :show, :create] do
    resources :forum_posts, only: [:create]
  end
  resources :monsters, only: [:index, :show] do   # 몬스터 도감
    member { post :evolve; post :set_active; post :feed }
  end
  resource  :shop, only: [:show]                   # 몬스터 케어/진화 아이템
  resources :purchases, only: [:create]
  resources :learn, only: [:index]           # 단계 학습 위저드

  # 담임교사
  namespace :teacher do
    resource  :dashboard, only: [:show]
    resources :reviews,  only: [:index, :show, :update] do
      member { post :approve; post :verify }
      collection { post :batch_approve }
    end
    resources :students, only: [:index, :create, :destroy] do
      member { post :reset_password; post :give_points }
    end
    resources :missions, :quizzes
    resource  :rubric_config, only: [:edit, :update]
  end

  # 교무관리자
  namespace :school_admin do
    resource  :stats, only: [:show]
    resources :neis, only: [:index]          # 생기부 자동요약
  end

  # 도서관 담당
  namespace :librarian do
    resource  :dashboard, only: [:show]
    resources :events
    resources :loans, only: [:index, :create] do   # 정보나루 동기화 + CSV 업로드
      collection { post :sync_data4library; post :import_csv }
    end
  end

  # 총괄관리자(superadmin)
  namespace :admin do
    root "analytics#show"
    resources :schools
    resources :users do
      member { post :suspend; post :reset_password; patch :role }
    end
    resources :books                          # 전역 콘텐츠
    resources :quizzes
    resources :badges, :shop_items, :monster_species  # 전역 콘텐츠(몬스터 도감 포함)
    resources :moderation, only: [:index] do
      member { post :hide; post :unhide }
    end
    resource  :settings, only: [:show, :update]
    resource  :analytics, only: [:show] do
      get :export                             # 전교 CSV
    end
  end

  # Solid Queue 대시보드(엔진, superadmin 인증 뒤)
  # mount MissionControl::Jobs::Engine, at: "/admin/jobs"  # (선택)
end
```

---

## 9. OCR · AI · 외부 서비스 설계

### 9.1 공통 원칙
- 모든 외부 호출은 **서버 서비스 객체**에서. 키는 `Rails.application.credentials`.
- 느린 호출(OCR·첨삭)은 **Solid Queue 잡**으로 비동기 → 완료 시 **Turbo Stream** 방송으로 UI 갱신.
- 각 서비스는 **키 없으면 폴백**(교체형 모듈 원칙, `연구/03_API연동_설계서.md`).

### 9.2 Ai::GeminiClient
- `POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=…`
- 입력: `{contents, systemInstruction, generationConfig}`. `generationConfig.responseMimeType: "application/json"`로 구조화 출력.
- credentials: `gemini.api_key`.

### 9.3 Ai::OcrService (Vision OCR)
- 입력: Active Storage 이미지 → base64 `inlineData` + `OCR_PROMPT`(손글씨 전사, temperature 0.1).
- 출력: 인식 텍스트 → `report.body` 초안. 학생이 편집(사람 확인 루프 = [6국03-05]).
- **키 없으면**: 사진(OCR) 입력 모드를 **비활성화**하고 "키보드/원고지로 입력해 주세요" 안내(사용자 확정 사항 — Tesseract 폴백 없음).
- 흐름: `OcrController#create`(업로드) → `OcrJob` → `report.update(body:, ai_status: :done)` → Turbo Stream으로 에디터 갱신.

### 9.4 Ai::ReviewService (5축 첨삭)
- 입력: 본문 + 책 정보 + `RUBRIC_PROMPT`(5축 루브릭·성취기준 주입).
- 출력(JSON 검증): `{ level:"A|B|C", rubric:{content,emotion,life,structure,spelling}, praise:[], fix:[], grow:[{text, standard_code}], pts }`. 포인트 A30/B20/C10.
- **폴백**: `Ai::RuleBasedReview`(키워드·길이·구조 휴리스틱) — 키 없거나 실패 시. **AI 첨삭 폴백은 유지**(OCR 폴백만 제거).
- 흐름: 제출 → `AiReviewJob` → 결과 저장 → 교사 검토 큐에 Turbo Stream 추가.

### 9.5 Ai::QuizDraftService / Ai::VerifyService
- 퀴즈 초안 생성(`QUIZGEN_SYS`) → 교사 검수 후 출제.
- 진위·표절(`VERIFY_PROMPT`) → 교사 검토 보조 + `report.similarity`(학급 내 유사도, Ruby로 계산).

### 9.6 Books::SearchService
- Kakao(`dapi.kakao.com/v3/search/book`, `KAKAO_REST_KEY`) → 실패 시 Naver(`openapi.naver.com/v1/search/book.json`, `NAVER_CLIENT_ID/SECRET`).
- 정규화: `{title, author, publisher, thumbnail, isbn, description}`. 결과를 `books`에 `category: searched`로 캐시.

### 9.7 Library::Data4libraryService (신규)
- 정보나루 `data4library.kr` 인기대출 OpenAPI(`DATA4LIBRARY_KEY`). 사서 대시보드 "인기 도서" 실제 집계.
- `library_loans`에 upsert. CSV 업로드(`import_csv`)와 병행(교육청 DLS는 공개 API 없음 → CSV 대안).

### 9.8 credentials 구조
```yaml
gemini:        { api_key: "..." }
kakao:         { rest_key: "..." }
naver:         { client_id: "...", client_secret: "..." }
data4library:  { api_key: "..." }
```

---

## 10. 실시간(Hotwire/Turbo) 설계

Firebase Realtime 동기화 목표를 **Turbo Streams + Solid Cable**로 대체.

| 이벤트 | 방송 | 구독 화면 |
|--------|------|-----------|
| 학생 제출 → AI 첨삭 완료 | `broadcast_append_to [classroom, :review_queue]` | 교사 검토 큐 |
| 교사 승인·코멘트 | `broadcast_replace_to [user, :reports]` | 학생 "내 서재"/알림 |
| 포인트 지급·레벨업 | `broadcast_update_to [user, :points]` | 학생 헤더 |
| 몬스터 진화·신규 발견 | `broadcast_replace_to [user, :active_monster]` | 학생 헤더·도감 |
| 랭킹 갱신 | `broadcast_replace_to [classroom, :ranking]` | 랭킹 화면 |
| 게시판 응원/스티커 | Turbo Stream | 우수작 게시판 |

- 모델에 `broadcasts_to ->(r){ [r.classroom, :review_queue] }` 등 선언.
- 비동기 잡 완료 콜백에서 방송(`Turbo::StreamsChannel.broadcast_*`).

---

## 11. 프론트엔드 라이브러리·API 검토 (Keep/Remove/Change)

프로토타입 외부 의존은 **Pretendard + Tesseract.js 단 2개**, 나머지는 브라우저 내장.

| 프로토타입 요소 | 처리 | Rails 구현 |
|------|------|-----------|
| Tesseract.js (CDN) | **제거** | OCR은 서버 Gemini만 |
| Pretendard (CDN @import) | **Keep · self-host** | `app/assets` 번들, CDN 제거 |
| Web Speech STT/TTS | **Keep** | `speech_controller.js`(Stimulus), UDL |
| MediaRecorder 낭독 녹음 | **Keep** | `recorder_controller.js` + Active Storage `audio` |
| Canvas 이미지 압축 | **Keep** | `photo_upload_controller.js`(업로드 경량화) |
| Canvas OCR 전처리 | **서버 이관/축소** | 원본 업로드 후 서버 처리(Gemini) |
| Canvas 성장 카드 PNG | **Keep** | `growth_card_controller.js` |
| 원고지 200칸 그리드 | **Keep** | `wongoji_controller.js` |
| Inline SVG 방사형(5축) | **Keep** | ViewComponent(서버 렌더) |
| SVG 아바타(6슬롯 합성) | **제거** | 반려 몬스터 이미지(도감·진화)로 대체 |
| window.print() PDF | **Keep** | print CSS + 전용 레이아웃 |
| `/gemini` 프록시 | **→ 서버 서비스** | `Ai::*` + 잡 |
| `/spell`(Daum) | **제거** | `spelling` 축이 대체 |
| `/booksearch`(Kakao/Naver) | **→ 서버 서비스** | `Books::SearchService` |
| 정보나루 API | **신규** | `Library::Data4libraryService` |
| schools.js(6,331교) | **→ DB 시드** | `schools` 테이블 |
| build.mjs 단일파일 빌드 | **제거** | 에셋 파이프라인 |
| Netlify/CF/Vercel 프록시 | **제거** | Rails 서버 |
| localStorage `chaek_db2` | **제거** | SQLite |

---

## 12. 디자인 시스템 (DESIGN.md)

- 리포지토리 루트에 **`DESIGN.md`** 신규 작성(별도 산출물). 내용:
  - **컬러 토큰** — 아동친화 팔레트, 라이트/다크, 명도대비 AA(≥4.5:1).
  - **타이포** — Pretendard 스케일, 본문/제목/캡션.
  - **스페이싱·라운드·섀도** 토큰.
  - **컴포넌트 스펙** — 카드, 사이드바 콘솔(담임), 포디움 Top3, 책 발견 캐러셀, 5축 방사형, **몬스터 도감 그리드·몬스터 카드·진화 로드맵·케어 상점**, 뱃지, 진행 바.
  - **상태·인터랙션** — 로딩("AI 첨삭 중"), 빈 상태, 에러/폴백 배너.
- **tailwindcss-rails**의 `tailwind.config`(또는 v4 `@theme`)를 `DESIGN.md` 토큰과 1:1 매핑.
- 기존 룩앤필에 얽매이지 않는 **새 디자인**을 이 문서 기준으로 구현. (본 계획서는 토큰 값 자체는 정의하지 않음 — `DESIGN.md`에서 확정.)

---

## 13. 도메인 상수 (프로토타입 이식)

DB가 아닌 **Ruby 상수/시드**로 이식(`config/` 또는 `app/models/concerns`).

### 13.1 5축 루브릭 · 성취기준 (2022 개정 국어, 학년군별 분기)

대상이 초등 **전학년**이므로 5축(키 고정)의 **성취기준·프롬프트 눈높이·추천활동을 학년군별로 분기**한다.
학생 학급 학년(`classroom.grade`)으로 학년군을 판별(`ReadingDomain.band_for`: 1·2→g12, 3·4→g34, 5·6/미상→g56)해
개별 리포트 첨삭(`Ai::ReviewService`·`RuleBasedReview`·`QuizDraftService`)에 적용한다. 코드는 교육부 고시 제2022-33호 [별책 5] 원문 근거.

| 축(key) | 라벨 | 1~2학년군(g12) | 3~4학년군(g34) | 5~6학년군(g56) |
|---------|------|----------------|----------------|----------------|
| content | 내용 이해 | [2국02-03] 중심 내용 확인 | [4국05-01] 인물·이야기 흐름 | [6국05-03] 인물·사건·배경 |
| emotion | 감상 표현 | [2국05-02] 느낀 점 말하기 | [4국05-04] 감각적 표현·생각/느낌 | [6국03-03] 체험 감상 글 |
| life | 삶과 연결 | [2국02-04] 인물 마음 나와 견주기 | [4국05-02] 경험↔작품세계 비교 | [6국05-06] 삶 연관 성찰(★A 유도) |
| structure | 구성·근거 | [2국03-02] 문장으로 표현 | [4국03-01] 문단 구성·고쳐쓰기 | [6국03-05] 통일성 고쳐쓰기 |
| spelling | 맞춤법 | [2국04-02] 낱말 바르게 쓰기 | [4국04-03] 바른 문장 짜임 | [6국04-06] 표기·띄어쓰기 |

A/B/C 판정(등급 규칙도 학년군 눈높이로 분기, 포인트 A30/B20/C10):
- **g56**: A(삶 적극 연관·성찰) / B(감상 有, 삶 연결 약) / C(줄거리 위주) — 기존 기준.
- **g34**: A(인물·사건 이해 + 느낌/경험 연결 1개↑) / B(느낌 有, 경험 연결 약) / C(줄거리 위주).
- **g12**: A(내용 이해 + 느낌 1개↑ 솔직 표현) / B(느낌 약·줄거리 위주) / C(글 매우 짧음).

> **여러 학년을 섞어 집계하는 대시보드**(교사 대시보드·학교 통계·NEIS 요약)는 단일 학년군이 애매하므로
> `ReadingDomain`의 flat 기본 상수(=g56)를 그대로 사용한다(하위호환). 학년군 분기는 학생 개별 리포트 경로에만 적용.

### 13.2 트레이너(독서가) 레벨·칭호 (LEVEL_PATH)
> 식물 6단계 스프라이트는 **반려 몬스터 도감/진화가 대체**한다(§13.5). 포인트 임계는 트레이너 레벨·칭호와 랭킹 산정에 유지하되, 성장의 **시각 표현**은 몬스터가 담당한다.

| Lv | 칭호 | 임계 포인트 |
|----|------|-------------|
| 1 | 책읽기 새내기 | 0 |
| 2 | 책벌레 | 100 |
| 3 | 이야기 탐험가 | 250 |
| 4 | 독서 모험가 | 450 |
| 5 | 책갈피 지킴이 | 700 |
| 6 | 책갈피 마스터 | 1000 |
- 레벨업마다 **새 몬스터 발견(해금)** 트리거(§13.5 획득 규칙).

### 13.3 뱃지 9종 / 위저드 5단계 / 게임 5종
- 뱃지: first, three, ten, levelA, tripleA, reviser, grower, challenger, ocr, **first_evolve(첫 진화), dex_half(도감 절반), dex_complete(도감 완성), final_form(첫 완전진화)**.
- 위저드: 책 고르기[6국02-05] → 줄거리[6국05-03] → 인상 깊은 장면[6국05-04] → 내 생각·느낌[6국03-03] → 삶과 연결[6국05-06].
- 게임: quiz, classic, vocab, whoami, book.

### 13.4 프롬프트
`OCR_PROMPT`, `RUBRIC_PROMPT`, `VERIFY_PROMPT`, `QUIZGEN_SYS` — 프로토타입에서 원문 이식 후 JSON 스키마 강제.

### 13.5 반려 몬스터 도감·진화 (신규 — 아바타 대체)

**컨셉**: 아바타 대신 학생마다 반려 몬스터를 **수집(도감)** 하고 **진화**시킨다. 성장의 시각 표현이자 지속 독서 동기 장치. 성장 6단계 식물 스프라이트를 대체.

**도감 규모**: 진화 라인 20~30개(초기 12개 시드 → 확장). 각 라인 3단계(기본형→성장형→완전형). 이미지는 외부 이미지 생성 AI로 제작하되 **완전 오리지널**(포켓몬 등 기존 IP 모방 금지 — 법적·대회 리스크). 일관 아트 가이드: 애니메이션 WebP, **5등신 비례**(최근 캐릭터 재설계와 정합), 통일된 라인·컬러 톤.

**속성(element)**: story/knowledge/emotion/adventure/nature/imagination — 도서 카테고리·장르와 느슨히 연동(예: 상상=판타지, 지식=고전/비문학).

**획득(수집) 규칙 — 노력 기반, 가챠 금지**:
- 첫 스타터: 서로 다른 속성 3종 중 **선택**.
- 이후: 트레이너 레벨업, 챌린지 완료, 특정 뱃지 획득, 도서 카테고리 최초 달성 등 **마일스톤마다 새 몬스터 발견**(알 부화 연출). 랜덤 뽑기·유료 요소 없음.

**진화 규칙 — 포인트 임계 + 독서 행동 조건(핵심)**:
진화 조건을 포인트만으로 두지 않고 "유도하고 싶은 독서 습관"과 결합한다. 라인마다 성격이 달라 서로 다른 습관을 자극:

| 예시 라인(속성) | 1→2 조건 | 2→3(완전형) 조건 |
|------|----------|-------------------|
| 이야기(story) | 포인트 100 + 독후감 3편 | 포인트 450 + A등급 2회 |
| 지식(knowledge) | 포인트 100 + 서로 다른 장르 2권 | 포인트 450 + 고전 1권 완독 |
| 감성(emotion) | 포인트 100 + 감상 표현 축 우수 | 포인트 700 + A등급(삶과 연결) 3회 |
| 모험(adventure) | 포인트 100 + 연속 독서 3일 | 포인트 700 + 연속 독서 스트릭 7일 |
| 자연(nature) | 포인트 100 + 미션 1회 참여 | 포인트 450 + 고쳐쓰기 향상 1회 |
| 상상(imagination) | 포인트 250 + 퀴즈/게임 3회 | 포인트 700 + 도감 5종 수집 |

- 조건 판정: `Evolvable` concern이 report 승인·포인트 지급·뱃지 획득 시점에 후크로 평가 → 충족 시 "진화 가능!" 표시, 학생이 진화 실행(연출) 또는 자동.
- **질 우선 정렬**: 완전형(3단계) 조건에 A등급·삶과 연결·고전·고쳐쓰기 등을 배치해 게임화를 §1.3 "발전적 첨삭" 가치와 정렬.
- 진화의 돌·먹이(상점 아이템)로 특정 조건 가속/충족 보조 가능(포인트 sink).

**랭킹·명예의 전당 연동**: 성장 기반 랭킹 신호 = 도감 완성도 + 진화 성취(완전형 수). 진화 단계가 포디움·프로필의 시각 신호로 노출.

> **→ 상세 시드**: 24라인(6속성×4계열)×3단계 = 72폼의 이름·콘셉트·진화 조건·AI 이미지 프롬프트·기계 판독용 YAML은 `연구/12_몬스터도감_시드.md` 참조. Phase 1은 12라인부터 시드.

---

## 14. 배포 (DigitalOcean + Kamal 2)

### 14.1 인프라
- **드로플릿** 1대(Ubuntu 24.04, 2GB+). Docker.
- **퍼시스턴트 볼륨** 마운트 → 컨테이너 재배포에도 데이터 보존:
  - `/rails/storage` = SQLite(primary + `queue`/`cache`/`cable`) + Active Storage 파일.
- **kamal-proxy**: 도메인 연결 + Let's Encrypt 자동 SSL.

### 14.2 config/database.yml (production 다중 DB)
```yaml
production:
  primary:  { <<: *default, database: storage/production.sqlite3 }
  cache:    { <<: *default, database: storage/production_cache.sqlite3, migrations_paths: db/cache_migrate }
  queue:    { <<: *default, database: storage/production_queue.sqlite3, migrations_paths: db/queue_migrate }
  cable:    { <<: *default, database: storage/production_cable.sqlite3, migrations_paths: db/cable_migrate }
```

### 14.3 config/deploy.yml (Kamal 스케치)
```yaml
service: chaekgalpi
image: <레지스트리>/chaekgalpi
servers:
  web: [ "<droplet-ip>" ]
proxy:
  ssl: true
  host: chaekgalpi.example.com
volumes:
  - "chaekgalpi_storage:/rails/storage"
env:
  clear:  { RAILS_ENV: production, SOLID_QUEUE_IN_PUMA: true }
  secret: [ RAILS_MASTER_KEY, GEMINI_API_KEY, KAKAO_REST_KEY,
            NAVER_CLIENT_ID, NAVER_CLIENT_SECRET, DATA4LIBRARY_KEY ]
```
- `SOLID_QUEUE_IN_PUMA: true` → 별도 워커 없이 Puma 내에서 잡 실행(소규모 적합).
- `.kamal/secrets`에서 환경변수 주입(git 커밋 금지).

### 14.4 배포 순서
1. `kamal setup`(최초) → 이후 `kamal deploy`.
2. 볼륨 생성 확인 → `kamal app exec "bin/rails db:prepare"`.
3. 시드: `kamal app exec "bin/rails db:seed"`(6,331 학교 + 데모).

---

## 15. 보안 · 개인정보 · 규정

- **API 키는 서버에만** — credentials/ENV, git 커밋 금지, 클라이언트 노출 금지.
- **연령제한 회피** — 학생이 외부 AI 직접 호출 금지, 반드시 서버 경유(대회 등외 방지 절대요건). Rails 서버 구조로 자동 충족.
- **비밀번호** — `has_secure_password`(bcrypt), 평문 `1234` 폐지(초기 발급/초기화 시에도 해시 저장).
- **개인정보 범위 제한** — 독후감·손글씨 사진은 **학급 범위**로만 접근(Pundit scope). 외부 학습 비전송 옵션.
- **파일 크기/검증** — Active Storage content_type·용량 검증.
- **CSRF/파라미터** — Rails 기본 + Strong Parameters.
- **정적분석** — `brakeman` CI.

---

## 16. 단계별 태스크 체크리스트

### Phase 1 — 스캐폴드 · 기반
- [ ] `rails new chaekgalpi -d sqlite3 -c tailwind`(Rails 8), Solid Queue/Cache/Cable 설치·마이그레이션
- [ ] Gemfile 확정(§4), `bundle`, importmap/turbo/stimulus 확인
- [ ] `DESIGN.md` 작성 + Tailwind 토큰 매핑, Pretendard self-host
- [ ] Pundit·Active Storage 셋업, `Current` 세팅
- [ ] 인증: 커스텀 SessionsController(튜플 신원) + `has_secure_password`
- [ ] `role` enum(superadmin 포함) 정의
- [ ] `lib/tasks/schools.rake` — schools.js → schools 테이블 시드(6,331)

### Phase 2 — 핵심 도메인
- [ ] 마이그레이션: schools/classrooms/users/reports/books
- [ ] 가입(학생·교사)·로그인·학교 검색 자동완성(JSON)
- [ ] 역할별 대시보드 셸 + Hotwire 네비(student/teacher/school_admin/librarian/superadmin)
- [ ] Pundit 정책 뼈대 + policy_scope

### Phase 3 — 독후감 파이프라인 (핵심 가치)
- [ ] 3입력 모드: 키보드 / 원고지(`wongoji_controller`) / 사진 OCR 업로드
- [ ] Active Storage(photo/drawing/audio)
- [ ] `Ai::GeminiClient` + `Ai::OcrService`/`OcrJob` + 사진모드 키없음 비활성 처리
- [ ] `Ai::ReviewService` + `Ai::RuleBasedReview` 폴백 + `AiReviewJob`
- [ ] 5축 루브릭 산출(`RubricScorable`, A/B/C·포인트)
- [ ] 교사 검토·5축 조정·코멘트·승인(`teacher/reviews`) + Turbo Stream 실시간 큐
- [ ] 고쳐쓰기 diff·향상도(`improvement`), 진위·유사도(`Ai::VerifyService`, `similarity`)
- [ ] 중간 검사(맞춤법은 Gemini `spelling` 축/규칙 사전으로 축소)

### Phase 4 — 게이미피케이션
- [ ] 포인트/트레이너 레벨(`Pointable`/`Leveling`) + 칭호
- [ ] **반려 몬스터 도감**: `monster_species`/`user_monsters` 마이그레이션 + 시드(초기 12라인×3단계)
- [ ] **몬스터 획득**(스타터 선택 + 마일스톤 발견) · **진화 엔진**(`Evolvable`: 포인트+독서행동 조건 평가) + 진화 연출(Turbo Stream)
- [ ] 몬스터 케어/진화 아이템 상점(shop_items/purchases 피벗) + `monster_component`/`dex_component`
- [ ] 뱃지 13종(`Badgeable`, 진화·도감 뱃지 포함) + 획득 트리거
- [ ] 3단 랭킹(class/school/nation) + 포디움 + 명예의 전당(도감·진화 성취 반영)
- [ ] 미션·챌린지·시즌

### Phase 5 — 콘텐츠 · 커뮤니티
- [ ] 도서 카탈로그(44+고전 시드) + `Books::SearchService` 자동완성/표지
- [ ] 우수작 게시판(board_posts/cheers/stickers) + 토론방(topics/forum_posts)
- [ ] 단계 학습 위저드(5단계)
- [ ] 독서게임 5종(quiz·classic·vocab·whoami·book)

### Phase 6 — 역할 도구
- [ ] 교사: 대시보드·5축 인사이트·CSV 내보내기·PDF(표창장/가정통신문/포트폴리오/성장리포트/성장카드 PNG)
- [ ] 교무관리자: 전교 통계 + NEIS 생기부 자동요약·복사
- [ ] 사서: 대시보드 + `Library::Data4libraryService` 동기화 + DLS CSV 업로드 + 이달의 책·행사

### Phase 7 — 총괄관리자(superadmin)
- [ ] `/admin` 네임스페이스 + 정책 격리
- [ ] 학교·사용자 관리(등록/승인/정지/역할/초기화)
- [ ] 전역 콘텐츠(도서·고전·전역 퀴즈·뱃지·상점·**몬스터 도감**)
- [ ] 시스템 설정(app_settings 기능 플래그·기본 루브릭·시드 재생성)
- [ ] 전교 통합 통계 + CSV 내보내기
- [ ] 모더레이션(게시판/토론 hide/unhide, 신고)

### Phase 8 — 배포
- [ ] Dockerfile/Kamal `deploy.yml` + 볼륨 + secrets
- [ ] `kamal setup`/`deploy`, SSL, `db:prepare`/`db:seed`
- [ ] 스모크·폴백 데모 검증(§17)

---

## 17. 검증 계획

| 항목 | 방법 |
|------|------|
| 핵심 플로우 | Capybara 시스템 테스트: 학생 작성 → OCR/AI 첨삭 → 교사 승인 → 포인트·레벨 반영 end-to-end |
| 실시간 | 교사·학생 2세션에서 Turbo Stream 반영(제출 → 검토 큐 즉시 표시, 승인 → 학생 즉시 반영) |
| 키 없는 폴백 | `GEMINI_API_KEY` 미설정 시: AI 첨삭 규칙기반 무중단, 사진 OCR 모드 안내와 함께 비활성, 키보드·원고지 정상 |
| 외부 연동 | Kakao/Naver·정보나루 키 설정 시 실제 응답, 실패 시 graceful 폴백 |
| 인가 경계 | Pundit 정책 테스트: 학생/교사/교무/사서/총괄 경계 위반 차단 |
| 배포 영속성 | 드로플릿 재배포 후 볼륨 데이터 유지, SSL, 시드 확인 |
| 데이터 무결성 | 모델 유효성·유니크 제약(튜플 신원, 학급 유일성) 테스트 |
| 검증 대회 요건(연구06) | CSV 원자료 내보내기(사전·사후 5축 비교용) 동작 확인 |

---

## 18. 마이그레이션 노트 (프로토타입 → Rails 매핑)

| 프로토타입 | Rails |
|------------|-------|
| `DB.load/save` + `db={}` | ActiveRecord + SQLite |
| `render()`/`*Shell()` 가상 라우팅 | 컨트롤러 + 역할별 레이아웃 + Turbo |
| `me()`/`session`(모듈 변수) | `Current.user` + 세션 쿠키 |
| `ckey`(school|grade|class 문자열) | `Classroom` 모델 |
| `mkStudent()`/`seed()` | `db/seeds.rb` + FactoryBot(테스트) |
| `aiReviewLLM`/`aiReview` | `Ai::ReviewService`/`Ai::RuleBasedReview` |
| `geminiOCR`/Tesseract 폴백 | `Ai::OcrService`(폴백 제거) |
| `spellCheckAsync`(Daum) | 제거(`spelling` 축) |
| `loadCovers`/`booksearch` | `Books::SearchService` + `books` 캐시 |
| `db.dls` | `library_loans` + 정보나루 |
| `wear`(아바타 6슬롯) / 아바타 상점 | `user_monsters`+`monster_species`(도감·진화), 상점=몬스터 케어/진화 아이템 |
| `exportCSV`/`printCert` 등 | 서버 CSV·print 레이아웃 |
| Netlify Functions 3종 | Rails 서비스 객체 |
| `build.mjs`/단일파일 | 폐기(에셋 파이프라인) |

---

### 참고 문서
- 코드 구조·데이터 모델: `연구/11_프로젝트_분석_보고서.md`
- 비전·성취기준·Must-Keep: `연구/01_연구분석_종합.md`, `연구/09_개발보고서.md`
- API 계약(교체형 모듈): `연구/03_API연동_설계서.md`
- DB/동기화/인가 청사진: `연구/07_Firebase마이그레이션_설계.md`
- 커리큘럼/위저드: `연구/02_단계적독후감학습_커리큘럼.md`
- 검증 방법론: `연구/06_검증계획서.md`
- 환경·배포 메모: `연구/10_개발현황_핸드오프.md`
- 원본 소스: `prototype/index.html`, `prototype/schools.js`
```
