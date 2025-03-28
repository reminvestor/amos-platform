Rails.application.routes.draw do
  get "social_media_accounts/index"
  get "social_media_accounts/new"
  get "social_media_accounts/create"
  get "social_media_accounts/callback"
  get "social_media_accounts/disconnect"
  get "business_profiles/edit"
  get "business_profiles/update"
  get "campaign_tracking/open"
  get "campaign_tracking/click"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  
  # Devise routes for authentication
  devise_for :users, controllers: {
    registrations: 'users/registrations'
  }
  
  # Admin namespace
  namespace :admin do
    resources :imports, only: [:index] do
      collection do
        post :elearning
      end
    end
  end
  
  # Application routes
  resources :contacts
  resources :contact_groups
  resources :email_templates do
    member do
      post :test_email
    end
  end
  resources :campaigns do
    member do
      post :send_test
      post :schedule
      post :pause
      post :resume
      post :stop
      get :analyze
    end
  end
  
  # AI content generation routes
  get 'ai_content/new', to: 'ai_content#new', as: :new_ai_content
  post 'ai_content/generate', to: 'ai_content#generate', as: :generate_ai_content
  get 'ai_content/improve/:template_id', to: 'ai_content#improve', as: :improve_ai_content
  post 'ai_content/improve/:template_id', to: 'ai_content#improve'
  get 'ai_content/analyze_campaign/:campaign_id', to: 'ai_content#analyze_campaign', as: :ai_analyze_campaign
  
  # Email tracking routes
  get 'campaign_tracking/open/:id', to: 'campaign_tracking#open', as: :email_open
  get 'campaign_tracking/click/:id', to: 'campaign_tracking#click', as: :email_click
  
  # Defines the root path route ("/")
  root "home#index"
  
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"

  resources :social_posts do
    member do
      post :publish
    end
    collection do
      post :generate_content
    end
  end

  # Business profile settings
  resource :business_profile, only: [:edit, :update] do
    member do
      post :add_knowledge
    end
  end

  # Social media account management
  resources :social_media_accounts, only: [:index, :new, :create] do
    collection do
      get 'auth/:platform', to: 'social_media_accounts#new', as: :auth
      get 'callback/:platform', to: 'social_media_accounts#callback', as: :callback
      delete 'disconnect/:id', to: 'social_media_accounts#disconnect', as: :disconnect
    end
  end
end
