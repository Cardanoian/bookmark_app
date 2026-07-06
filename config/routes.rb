Rails.application.routes.draw do
  root "dashboard#show"

  # 인증 (튜플 신원)
  resource  :session, only: [ :new, :create, :destroy ]
  resources :registrations, only: [ :new, :create ]
  get "schools/search", to: "schools#search", as: :schools_search

  # 학생 영역 — 독후감 CRUD + 3 입력 모드 + 고쳐쓰기·공유
  resources :reports do
    member do
      post :revise
      post :share
    end
  end
  resource :ocr, only: [ :create ], controller: "ocr"

  # 도서 검색·카탈로그 (P5.1/P5.2)
  resources :books, only: [ :index, :show ] do
    collection { get :search }
  end

  # 단계 학습 위저드 5단계 (P5.5) — 세션 진행 저장, 완료 시 독후감 초안 연결.
  resources :learn, only: [ :index ] do
    collection { post :advance }
  end

  # 독서게임 10종 (P5.6). quiz/golden/bingo 는 published 퀴즈를 소비하는 실동작 게임,
  # 나머지 7종은 증분(라우트 + 플레이스홀더). 결과는 games/attempts 로 기록.
  namespace :games do
    resources :book, :classic, :battle, :balance, :quiz,
              :golden, :bingo, :vocab, :whoami, :marathon, only: [ :show ]
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
  resources :missions, only: [ :index, :show ] do
    member { post :join }
  end
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

    resources :missions
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
