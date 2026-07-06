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
