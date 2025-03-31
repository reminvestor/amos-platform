Rails.application.routes.draw do
  # Heroku health check
  get 'health_check' => proc { [200, {}, ['OK']] }
  
  # Diagnostic route for SSL/headers issues
  get 'debug_headers' => proc { |env| 
    headers = env.select { |k, v| k.start_with?('HTTP_') || ['HTTPS', 'REQUEST_METHOD', 'REQUEST_URI', 'rack.url_scheme'].include?(k) }
    [200, {'Content-Type' => 'application/json'}, [headers.to_json]] 
  }
  
  # API routes
  namespace :api do
    namespace :v1 do
      # Health check endpoint
      get 'health', to: 'health#index'
      resources :contacts, only: [:create]
    end
  end
  
  # Routes with constraints on subdomain - application routes for 'app' subdomain
  constraints(lambda { |req| req.subdomain == 'app' }) do
    # Devise routes for authentication
    devise_for :users, controllers: {
      registrations: 'users/registrations'
    }
    
    # User management
    resources :users, only: [:show, :edit, :update]
    
    # Admin namespace
    namespace :admin do
      resources :imports, only: [:index] do
        collection do
          post :elearning
        end
      end
    end
    
    # Entity management
    resources :entities do
      member do
        get :switch
      end
    end
    
    # Application routes
    resources :contacts
    resources :contact_groups do
      collection do
        get :search_contacts
      end
      member do
        post :upload_csv
      end
    end
    resources :email_templates do
      member do
        post :test_email
      end
    end
    resources :campaigns do
      member do
        post :send_test
        post :schedule
        post :send_now
        post :pause
        post :resume
        post :stop
        post :reactivate
        post :sync_mailgun
        get :analyze
      end
    end
    
    # AI content generation routes
    get 'ai_content/new', to: 'ai_content#new', as: :new_ai_content
    post 'ai_content/generate', to: 'ai_content#generate', as: :generate_ai_content
    get 'ai_content/improve/:template_id', to: 'ai_content#improve', as: :improve_ai_content
    post 'ai_content/improve/:template_id', to: 'ai_content#improve'
    get 'ai_content/analyze_campaign/:campaign_id', to: 'ai_content#analyze_campaign', as: :ai_analyze_campaign
    post 'ai_content/reanalyze_campaign/:campaign_id', to: 'ai_content#reanalyze_campaign', as: :reanalyze_campaign
    
    # Email tracking routes
    get 'campaign_tracking/open/:id', to: 'campaign_tracking#open', as: :email_open
    get 'campaign_tracking/click/:id', to: 'campaign_tracking#click', as: :email_click
    
    # Subscription management
    get 'unsubscribe', to: 'subscription#unsubscribe', as: :unsubscribe
    
    # Social media routes
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
    
    # Application root for authenticated subdomain
    root "home#index", as: :application_root
  end
  
  # Routes for marketing site (no subdomain or www subdomain)
  constraints(lambda { |req| !req.subdomain.present? || req.subdomain == 'www' }) do
    # Marketing site routes
    get '/', to: 'marketing#index', as: :marketing_root
    get '/features', to: 'marketing#features', as: :marketing_features
    get '/pricing', to: 'marketing#pricing', as: :marketing_pricing
    get '/about', to: 'marketing#about', as: :marketing_about
    get '/contact', to: 'marketing#contact', as: :marketing_contact
    
    # Set the root path for marketing site
    root 'marketing#index'
  end
  
  # Common routes (regardless of subdomain)
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
