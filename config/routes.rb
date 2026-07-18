Rails.application.routes.draw do
  root "dashboard#show"

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

  resources :registrations, only: [ :new, :create ]
  resource :profile, only: [ :show ]
  # 학생 정보구조(menu_refactor 심화 PR5): 내 서재(책별 활동 포트폴리오) + 독서활동(책 선택→독후감/게임 허브).
  resource :library, only: [ :show ], controller: "libraries"
  resource :reading_activity, only: [ :show ], controller: "reading_activities"
  # 본인 비밀번호 변경(역할 무관, current_user 대상). 현재 비번 확인 후 변경.
  get   "profile/password", to: "passwords#edit",   as: :edit_password
  patch "profile/password", to: "passwords#update", as: :password
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

  # 도서 검색·카탈로그 (P5.1/P5.2)
  #   search    = 네이버+로컬 폴백 검색(무키 로컬 LIKE), 결과를 searched 로 캐시. 독후감 자동완성용(id 포함).
  #   autocomplete = 로컬 카탈로그(비-searched) 전용 자동완성(외부호출 0). 퀴즈·게임 도서 선택용.
  resources :books, only: [ :index, :show ] do
    collection do
      get :search
      get :autocomplete
      get :remote_search
    end
  end

  # 단계 학습 위저드 5단계 (P5.5) — 세션 진행 저장, 완료 시 독후감 초안 연결.
  resources :learn, only: [ :index ] do
    collection { post :advance }
  end

  # 독서게임 5종 (P5.6 → Phase 3 온디맨드). 카탈로그에서 도서를 골라 `play?book_id=` 로 온디맨드
  # 진입한다(미스=오프라인 즉시). 4종은 퀴즈 파이프라인 실동작(quiz·classic=mcq·vocab=matching·
  # whoami=hint_reveal), 1종은 소셜 도메인(book=책 소개 대결, Gemini 미호출). 결과는 games/attempts 로
  # 기록(book 제외). quiz 는 교사 published 퀴즈(id) show 도 병행 지원(mcq 퀴즈 단일 재생 경로).
  namespace :games do
    get "catalog", to: "catalog#index", as: :catalog

    # 온디맨드 진입(book_id) — 퀴즈 파이프라인 4종 표면의 play. `:id` show 보다 먼저 선언해 "play" 가
    # id 로 오인되지 않게 한다(games_<표면>_play_path).
    %w[quiz classic vocab whoami].each do |surface|
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
  # 토론 글 좋아요(👍, P5.4). forum_post_id 만으로 create/destroy(단수 like 리소스).
  resources :forum_posts, only: [] do
    resource :like, only: [ :create, :destroy ], controller: "forum_post_likes"
  end

  # 게임화 — 몬스터 도감·진화, 케어 상점, 랭킹, 미션·챌린지
  resources :monsters, only: [ :index, :show ] do
    member do
      post :evolve
      post :set_active
      post :feed
    end
    collection do
      post :choose_starter
    end
  end
  resource  :shop, only: [ :show ]
  resources :purchases, only: [ :create ]
  resources :rankings, only: [ :index ]
  # 미션은 상위 메뉴/독립 화면 없이 홈·독서활동 문맥에 노출한다(menu_refactor 심화 PR6 — 세션 참여방식 제거).
  # 자동 배정·자동 진행이라 학생 join 액션이 없다. challenge 는 이번 범위에서 세션 참여 유지.
  resources :challenges, only: [ :index, :show ] do
    member { post :join }
  end

  # 담임교사 — 검토 큐·5축 조정·승인·진위 확인 + 대시보드·학생관리·미션·퀴즈·루브릭·문서출력
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
      end
    end

    resources :missions do
      member { post :publish }
    end
    resources :quizzes
    resource  :rubric_config, only: [ :edit, :update ]

    # 문서 출력(대회요건 연구06 원자료 CSV + 인쇄용 HTML)
    get "exports/reports_csv", to: "exports#reports_csv", as: :exports_reports_csv
    resources :prints, only: [] do
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
    resources :books
    resources :quizzes
    resources :badges
    resources :shop_items
    resources :monster_species
    resources :moderation, only: [ :index ] do
      member do
        post :hide
        post :unhide
      end
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
