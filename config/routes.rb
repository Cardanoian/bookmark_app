Rails.application.routes.draw do
  root "dashboard#show"

  # Hotwire Native Android 앱이 받아가는 원격 Path Configuration(공개 정적 JSON).
  # 컨트롤러가 `ActionController::API` 를 직접 상속해 로그인·Pundit·allow_browser 를 타지 않는다
  # (사유는 `NativeConfigurationsController` 주석 참고). public/ 정적 파일로 두지 않는 이유는
  # production 의 1년 cache-control 이 "APK 재배포 없이 즉시 조정" 목적을 없애기 때문이다.
  # 호환성이 깨지는 규칙 변경은 이 파일을 덮어쓰지 않고 android_v2.json 을 추가한다.
  get "configurations/android_v1.json",
      to: "native_configurations#show", as: :android_v1_configuration

  # 인증 — 처음 접속 시 안내 인덱스(학생/교직원 선택) + 분리 로그인 + 공용 로그아웃.
  #   new(GET /session/new) = 안내 인덱스 선택 화면. 비로그인 접근 리다이렉트(require_login)가
  #     이 경로로 오므로, 앱에 처음 들어오면 학생·교직원 로그인을 고르는 화면이 뜬다.
  #   destroy(DELETE /session) = 로그아웃(전 역할 공용, 기존 로그아웃 버튼 재사용).
  resource :session, only: [ :new, :destroy ]
  # 학생 로그인 — 시도/시군구/학교/학급/이름/비밀번호(튜플 신원).
  get  "login/student", to: "sessions#student_new",    as: :student_login
  post "login/student", to: "sessions#student_create"
  # 교직원(교사·교무관리자·사서·총괄관리자) 로그인 — 이메일/비밀번호.
  get  "login/staff",   to: "sessions#staff_new",      as: :staff_login
  post "login/staff",   to: "sessions#staff_create"
  # 체험 계정 원클릭 로그인 — role(student|teacher)만 받고 계정은 서버가 확정(비밀번호 미전송).
  post "login/demo",    to: "sessions#demo_create",    as: :demo_login

  # 교직원 비밀번호 재설정(이메일 링크). **학생은 대상이 아니다** — 학생은 이메일 로그인 대상이
  # 아니고(튜플 로그인) 담임이 teacher/students#reset_password 로 직접 초기화한다. 컨트롤러가
  # `User#password_reset_eligible?`(staff? && email? && !suspended?)로 fail-closed 판정하며,
  # 계정 존재 여부는 응답으로 누설하지 않는다(존재·미존재·학생·정지 전부 동일 안내 화면).
  # 토큰은 DB 무저장 서명 토큰(`generates_token_for :password_reset`)이라 param 으로 받는다.
  resources :password_resets, only: [ :new, :create, :edit, :update ], param: :token

  # 교사 가입 이메일 인증. show=메일 링크(토큰, 비로그인 허용), create=재발송(로그인 필요).
  # 인증 미완료가 로그인을 막지는 않는다(가입 즉시 로그인 흐름 보존) — 유예 24시간이 지난 뒤
  # 학생 계정 생성·학생 비번 초기화만 제한한다(`User#email_verification_gate_active?`).
  # 리터럴 경로(resend)를 :token 보다 먼저 선언해 "resend" 가 토큰으로 오인되지 않게 한다.
  post "email_verification/resend", to: "email_verifications#create", as: :resend_email_verification
  get  "email_verification/:token", to: "email_verifications#show",   as: :email_verification

  resources :registrations, only: [ :new, :create ]
  resource :profile, only: [ :show ]
  resource :growth, only: [ :show ]
  # 사용방법 안내(학생 도움말, 정적 화면). 상단 학생 메뉴 "사용방법"의 목적지.
  resource :guide, only: [ :show ], controller: "guides"
  resource :ranking_preference, only: [ :edit, :update ]
  # 학생 정보구조(menu_refactor 심화 PR5): 내 서재(책별 활동 포트폴리오) + 독서활동(책 선택→독후감/게임 허브).
  resource :library, only: [ :show ], controller: "libraries"
  resource :reading_activity, only: [ :show ], controller: "reading_activities" do
    # 인근 도서관 대출 가능 표시(Turbo Frame lazy-load). book_id 는 쿼리로 전달.
    get :nearby_libraries
  end
  # 본인 비밀번호 변경(역할 무관, current_user 대상). 현재 비번 확인 후 변경.
  get   "profile/password", to: "passwords#edit",   as: :edit_password
  patch "profile/password", to: "passwords#update", as: :password
  # 계정 연동(MERGE) 학생 셀프서브(account_linking_seasons_plan §Phase 3). 학년이 바뀐 학생이 작년
  # 계정 자격증명을 증명해 병합한다: new(폼) → preview(인증·미리보기·서명토큰) → confirm(병합·세션 스왑).
  resource :account_link, only: [ :new ], controller: "account_links" do
    post :preview
    post :confirm
  end
  # 몬스터 발견 연출 확인(acknowledge) — 학생이 축하 모달을 본 뒤 celebrated_at 을 마킹(재노출 방지).
  post "discoveries/acknowledge", to: "discoveries#acknowledge", as: :acknowledge_discoveries
  # 학교 선택 하이브리드 피커(가입/로그인 공개). 이름검색(search) + 시군구 캐스케이딩(gus)
  # + 로그인 종속 학급(:id/classrooms). 리터럴 경로를 :id 보다 먼저 선언한다.
  get "schools/search", to: "schools#search", as: :schools_search
  get "schools/gus", to: "schools#gus", as: :schools_gus
  get "schools/:id/classrooms", to: "schools#classrooms", as: :school_classrooms

  # 학생 영역 — 독후감 CRUD + 3 입력 모드 + 고쳐쓰기·공유
  resources :reports do
    member do
      post :revise
      post :share
    end
  end
  resource :ocr, only: [ :create ], controller: "ocr"

  # OCR 손글씨 사진(아동 PII) 인증 프록시. Active Storage 서명 URL(무인가) 대신 매 요청
  # `ReportPolicy#show?` 를 강제해 페이지 인가와 동일한 경계로 바이트를 서빙한다.
  # `?size=original` 은 확대용 1600px 유계 variant(원본 바이트는 서빙하지 않음).
  get "reports/:id/photo", to: "report_photos#show", as: :report_photo

  # 위 경로는 이미지 **바이트**를 돌려준다. 앱(WebView)에서는 그 URL 로 이동할 방법이 없어
  # (`target="_blank"` 는 무시되고, target 을 빼면 Turbo 가 비-HTML 응답을 방문으로 처리해
  # 오류 화면으로 끝난다 — 계획 §N.5 실측) 이미지를 감싼 **HTML 화면**을 따로 둔다.
  # 웹은 기존 경로를 그대로 쓰므로 이 라우트는 순수 추가다.
  get "reports/:id/photo/zoom", to: "report_photos#zoom", as: :zoom_report_photo

  # 도서 검색·카탈로그 (P5.1/P5.2)
  #   search    = 네이버+로컬 폴백 검색(무키 로컬 LIKE), 결과를 searched 로 캐시. 독후감 자동완성용(id 포함).
  #   autocomplete = 로컬 카탈로그(비-searched) 전용 자동완성(외부호출 0). 퀴즈·게임 도서 선택용.
  #   volumes      = 시리즈 접기 드릴다운(시리즈→권 선택 2단계) 전용 권 목록(로컬, 외부호출 0).
  resources :books, only: [ :index, :show ] do
    collection do
      get :search
      get :autocomplete
      get :volumes
      get :remote_search
    end
  end

  # 단계 학습 위저드 5단계 (P5.5) — 세션 진행 저장, 완료 시 독후감 초안 연결.
  resources :learn, only: [ :index ] do
    collection { post :advance }
  end

  # 학생 출제 기여(전국 공유 문제은행 UGC, 게임 재구성 Phase 3 §4.1). 독서활동 화면에서 그 책의
  # 문제(객관식·나는 누구게? 힌트)를 낸다 → pending 저장 → 담임 검토 큐.
  # index 는 **본인이 낸 문제 모아보기**(마이페이지 진입) — 낸 뒤 검토·승인 결과를 확인할 곳이
  # 없어 학생이 자기 기여를 되짚을 수 없던 공백을 메운다.
  resources :quiz_contributions, only: [ :index, :new, :create ]

  # 독서게임 3종 (P5.6 → Phase 3 온디맨드 → 게임 재구성 Phase 1). 카탈로그에서 도서를 골라
  # `play?book_id=` 로 온디맨드 진입한다(미스=오프라인 즉시). 2종은 퀴즈 파이프라인 실동작
  # (quiz=mcq[고전 통합]·whoami=hint_reveal), 1종은 소셜 도메인(book=책 소개 대결, Gemini 미호출).
  # 결과는 games/attempts 로 기록(book 제외). quiz 는 교사 published 퀴즈(id) show 도 병행 지원
  # (mcq 퀴즈 단일 재생 경로). classic(→quiz 통합)·vocab(hard-delete) 표면은 제거됐다.
  namespace :games do
    get "catalog", to: "catalog#index", as: :catalog

    # 온디맨드 진입(book_id) — 퀴즈 파이프라인 표면의 play. `:id` show 보다 먼저 선언해 "play" 가
    # id 로 오인되지 않게 한다(games_<표면>_play_path).
    %w[quiz whoami].each do |surface|
      get "#{surface}/play", to: "#{surface}#play", as: "#{surface}_play"
    end

    # 교사 published mcq 퀴즈(id) show 병행 — quiz 로 단일화.
    resources :quiz, only: [ :show ]

    # whoami: show(=attempt id) 상태 렌더 + reveal_hint(서버 힌트 공개, §3.2b).
    resources :whoami, only: [ :show ]
    post "whoami/:attempt/reveal_hint", to: "whoami#reveal_hint", as: :whoami_reveal_hint

    # 책 소개 대결(book) — 퀴즈 파이프라인 밖 소셜 도메인. 도서별 소개 작성·또래 투표(경계=학급).
    get    "book/play",            to: "book#play",   as: :book_play
    post   "book/intros",          to: "book#create", as: :book_intros
    post   "book/intros/:id/vote", to: "book#vote",   as: :book_vote
    delete "book/intros/:id/vote", to: "book#unvote"

    # 뒷이야기 이어쓰기(sequel) — 창작 소셜 도메인(book 미러). 책 이후 이야기 작성·또래 공감(경계=학급) +
    # 제출 시 학생 글을 평가한 격려형 AI 코멘트 비동기(SequelFeedbackJob). 모든 책에서 항상 가능(학생 상상).
    get    "sequel/play",             to: "sequel#play",   as: :sequel_play
    post   "sequel/entries",          to: "sequel#create", as: :sequel_entries
    post   "sequel/entries/:id/vote", to: "sequel#vote",   as: :sequel_vote
    delete "sequel/entries/:id/vote", to: "sequel#unvote"

    # 다시 뽑기(§3.4) — 새 content_version 재생성 후 해당 표면 play 로 복귀. 콘텐츠 재생성이지
    # 가챠·랜덤 획득이 아니므로(포인트 상한 봉인) 경로명은 무가챠 가드 준수차 regenerate 로 둔다.
    post "regenerate", to: "regenerate#create", as: :regenerate

    # 콘텐츠 신고(무게이트 롤아웃 안전장치) — 서로 다른 2명 신고 시 자동 숨김+재생성, 신고자 학급
    # 담임이 대시보드에서 사후 검토. system(온디맨드) 판만 신고 대상(quiz_id 파라미터).
    post "content_reports", to: "content_reports#create", as: :content_reports

    resources :attempts, only: [ :create ]
  end

  # 커뮤니티 — 우수작 게시판(응원/스티커) + 토론방 (P5.3/P5.4)
  resources :board_posts, only: [ :index, :show ] do
    resources :cheers, only: [ :create, :destroy ]
    resources :stickers, only: [ :create ]
  end
  resources :topics, only: [ :index, :show, :create ] do
    resources :forum_posts, only: [ :create ]
  end
  # 토론 글 좋아요(👍, P5.4)·신고(🚩, reading_discussion). forum_post_id 만으로 단수 리소스.
  resources :forum_posts, only: [] do
    resource :like, only: [ :create, :destroy ], controller: "forum_post_likes"
    # 신고(1인 1신고). 자동 숨김 없이 저자 학급 담임 대시보드 사후 검토 신호가 된다.
    resource :report, only: [ :create ], controller: "forum_post_reports"
  end

  # 게임화 — 몬스터 도감·진화, 케어 상점, 랭킹, 미션·챌린지
  resources :monsters, only: [ :index, :show ] do
    member do
      post :evolve
      post :set_active
    end
    collection do
      post :choose_starter
    end
  end
  resources :rankings, only: [ :index ]
  # 미션은 학생 열람 전용 index·show 만 최상위 노출한다(challenge-mission-detail-pages — 사유=사용자
  # 요구: 홈은 개수 카드만, 상세 내역은 별도 목록·상세 화면). 관리 CRUD 는 teacher 네임스페이스에
  # 유지(발행·수정·삭제). PR6 의 "미션 독립 화면 없음" 원칙은 이 열람 전용 화면에 한해 의식적으로
  # 번복하되, MissionPolicy#index?(학생 전용)·#show?(학급 경계)를 필수전제로 결속해 유출을 막는다.
  resources :missions, only: [ :index, :show ]
  # 챌린지: 조회·참여(학생 join → 세션 플래그) + 관리 CRUD(교직원 — 총괄=전국, 교사·사서·교무=우리 학교).
  # scope·school_id 는 폼이 아니라 역할에서 파생(ChallengesController#apply_scope_from_role), 접근은 ChallengePolicy.
  resources :challenges do
    member { post :join }
  end

  # 담임교사 — 검토 목록·5축 조정·승인·진위 확인 + 대시보드·학생관리·미션·퀴즈·루브릭·문서출력
  namespace :teacher do
    resource  :dashboard, only: [ :show ]

    resources :reviews, only: [ :index, :show, :update ] do
      member do
        post :approve
        post :verify
      end
      collection do
        post :batch_approve
      end
    end

    resources :students, only: [ :index, :create, :destroy ] do
      member do
        post :reset_password
        post :give_points
        post :set_ai_consent
      end
    end

    # 학생별 통계(student-stats) — 읽기 전용. index=선택 학급(`?classroom_id=`) 학생 전원의
    # 독후감·게임·미션·챌린지 지표 표(`?sort=`), show=학생 1명 상세. 학생 '관리'(추가·삭제·비번)와
    # 축이 달라 students 와 분리한다(management vs analytics).
    resources :student_stats, only: [ :index, :show ]

    resources :missions do
      member { post :publish }
    end
    resources :quizzes
    # 학생 기여 문제 검토·수정 큐(게임 재구성 Phase 3 §4.3). 담임만 자기 학급 학생 pending 열람/수정/
    # 승인/반려. 승인 시 전국 공유 풀로 물질화(ContributionPublisher).
    resources :quiz_contributions, only: [ :index, :update ] do
      member do
        post :approve
        post :reject
      end
    end
    resource :rubric_config, only: [ :edit, :update ]

    # 토론 글 모더레이션(reading_discussion) — 담임이 자기 학급 학생 글만 숨김/해제(저자 학급 경계).
    post "forum_posts/:id/hide",   to: "forum_moderations#hide",   as: :forum_post_hide
    post "forum_posts/:id/unhide", to: "forum_moderations#unhide", as: :forum_post_unhide

    # 계정 연동(MERGE) 교사 보조(account_linking_seasons_plan §Phase 4 — 라우트 선점, 컨트롤러는 Phase 4).
    # 담임이 자기 학급 현재 학생을 작년 계정과 병합(owned_student! 강제)·되돌리기(reverse).
    resources :account_links, only: [ :index, :new, :create ] do
      member { post :reverse }
    end

    # 문서 출력(대회요건 연구06 원자료 CSV + 인쇄용 HTML)
    get "exports/reports_csv", to: "exports#reports_csv", as: :exports_reports_csv
    # index = 문서 출력 진입 화면(교사 네비 "문서 출력"). 4종 문서는 여기서만 링크된다.
    resources :prints, only: [ :index ] do
      collection do
        get :award         # 표창장
        get :home_letter   # 가정통신문
        get :portfolio     # 독서 포트폴리오
        get :class_report  # 학급 성장 리포트
      end
    end
  end

  # 교무관리자 — 전교 통계 + NEIS 생기부 자동요약(자기 학교 경계). (P6.4)
  namespace :school_admin do
    resource  :stats, only: [ :show ]
    resources :neis, only: [ :index ]
  end

  # 사서 — 도서관 대시보드 + 인기대출(정보나루/CSV) + 이달의 책·행사(자기 학교 경계). (P6.5)
  namespace :librarian do
    resource  :dashboard, only: [ :show ]
    resources :events
    resources :loans, only: [ :index, :create ] do
      collection do
        post :sync_data4library
        post :import_csv
      end
    end
  end

  # 총괄관리자(superadmin) — 전용 /admin 네임스페이스. Admin::BaseController 가드로
  # superadmin 이외 전 역할 403(정책 격리). (P7.1~P7.6)
  namespace :admin do
    root "analytics#show"

    resources :schools
    resources :users do
      member do
        post :suspend
        post :unsuspend
        post :reset_password
        patch :role
      end
    end
    resources :audit_logs, only: [ :index ]
    resources :books
    resources :recommendation_imports, only: [ :index, :create ]
    resources :quizzes
    resources :badges
    resources :monster_species
    resources :moderation, only: [ :index ] do
      member do
        post :hide
        post :unhide
      end
    end
    # 게임 콘텐츠 에스컬레이션(게임 재구성 Phase 3 §4.5) — 전국 노출 system 풀 퀴즈의 신고 콘텐츠를
    # 총괄이 영구 숨김/복원/삭제. 담임 대시보드(자기 학급 신호)와 별개의 전국 관점 중앙 큐.
    resources :game_contents, only: [ :index, :destroy ] do
      member do
        post :hide
        post :restore
      end
    end
    # 계정 연동(MERGE) 총괄 보조(account_linking_seasons_plan §Phase 4 — 라우트 선점, 컨트롤러는 Phase 4).
    # 전 학교 검색·감사·병합·되돌리기(총괄은 되돌리기 시간창 무제한).
    resources :account_links, only: [ :index, :create ] do
      member { post :reverse }
    end

    resource :settings, only: [ :show, :update ]
    resource :analytics, only: [ :show ]
    get "analytics/export", to: "analytics#export", as: :analytics_export
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
