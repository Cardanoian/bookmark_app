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

  # 담임교사 — 검토 큐·5축 조정·승인·진위 확인
  namespace :teacher do
    resources :reviews, only: [ :index, :show, :update ] do
      member do
        post :approve
        post :verify
      end
      collection do
        post :batch_approve
      end
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
