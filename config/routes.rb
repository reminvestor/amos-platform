require 'solid_queue'

Rails.application.routes.draw do
  # Health check endpoints - must be first!
  get 'up', to: 'health#up'
  get 'health', to: 'health#index'
  get 'health_check', to: 'health#up'
  
  get "crawler_jobs/index"
  get "crawler_jobs/new"
  get "crawler_jobs/create"
  
  # Diagnostic route for SSL/headers issues
  get 'debug_headers' => proc { |env| 
    headers = env.select { |k, v| k.start_with?('HTTP_') || ['HTTPS', 'REQUEST_METHOD', 'REQUEST_URI', 'rack.url_scheme'].include?(k) }
    [200, {'Content-Type' => 'application/json'}, [headers.to_json]] 
  }
  
  # ActionCable for real-time features
  mount ActionCable.server => '/cable'
  
  # API routes
  namespace :api do
    namespace :v1 do
      # Health check endpoint
      get 'health', to: 'health#index'
      resources :contacts, only: [:create]
      resources :jobs, only: [:show]
      post 'crawler_contacts', to: 'crawler_contacts#create'
      
      # Crawler Job Logging
      post 'crawler_jobs/:id/logs', to: 'crawler_job_logs#create'
      
      # Landing page form submissions
      resources :landing_page_submissions, only: [:create, :index, :show] do
        member do
          post :process
          post :spam
        end
        collection do
          get :export
        end
      end
      # Alternative route for submissions by landing page slug
      post 'landing_pages/:landing_page_slug/submit', to: 'landing_page_submissions#create'
    end
  end
  
  # Routes with constraints on subdomain - application routes for 'app' subdomain
  constraints(lambda { |req| req.subdomain == 'app' }) do
    # Solid Queue Interface
    authenticate :user, lambda { |u| u.admin? } do
      mount SolidQueueInterface::Engine => '/solid_queue'
    end
    
    # Devise routes for authentication
    devise_for :users, controllers: {
      registrations: 'users/registrations',
      sessions: 'users/sessions',
      passwords: 'users/passwords'
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
      
      resources :maintenance, only: [:index] do
        collection do
          post :add_missing_email_deliveries
          post :fix_campaign_entity_ids
          post :reprocess_drip_campaigns
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
    # Media library
    resources :image_assets, only: [:index, :new, :create, :show, :destroy] do
      collection do
        post :generate
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
        post :force_resume
        post :sync_mailgun
        get :analyze
        post :setup_drip
        post :trigger_drip
      end
    end
    
    # Landing pages
    resources :landing_pages do
      member do
        post :publish
        post :unpublish
        get :preview
        get :chat
        get :no_header_preview
        post :generate_content
        post :generate_image
        post :generate_images
        post :apply_change
        get :inline_edit
        get :get_chat_messages
        get :versions
        post 'rollback/:version_id', to: 'landing_pages#rollback', as: :rollback
        get :clarify
        post :answer_clarification
      end
    end
    
    # Public landing page view (no auth required)
    get 'landing/:slug', to: 'landing_pages#public_view', as: :landing_page_public
    
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
    
    # Crawler Jobs Management
    resources :crawler_jobs, only: [:index, :new, :create, :show] do
      member do
        post :execute
        post :test
        get :logs
        post :debug
        post :improve
        post :fix_bugs
        post :chat
        post :reset_conversation
      end
    end
    
    # Workspace routes (AI Chat Interface)
    # Application root for authenticated subdomain - Scout with intelligent canvas!
    root "scout#index", as: :application_root
  end
  
  # Routes for marketing site (no subdomain or www subdomain)
  constraints(lambda { |req| !req.subdomain.present? || req.subdomain == 'www' }) do
    # Marketing site routes
    get '/', to: 'marketing#index', as: :marketing_root
    get '/features', to: 'marketing#features', as: :marketing_features
    get '/pricing', to: 'marketing#pricing', as: :marketing_pricing
    get '/about', to: 'marketing#about', as: :marketing_about
    get '/contact', to: 'marketing#contact', as: :marketing_contact
    get '/help', to: 'marketing#help', as: :marketing_help
    post '/contact', to: 'marketing#contact_submit', as: :marketing_contact_submit
    
    # Set the root path for marketing site
    root 'marketing#index'
  end
  
  # Debug routes for troubleshooting 
  get 'debug', to: 'debug#index'
  get 'debug/status', to: 'debug#status'
  get 'debug/test_sse', to: 'debug#test_sse'
  
  # Onboarding routes
  get 'onboarding', to: 'onboarding#index'
  post 'onboarding/chat', to: 'onboarding#chat'
  patch 'onboarding/complete', to: 'onboarding#complete'
  get 'onboarding/reset', to: 'onboarding#reset'
  get 'onboarding/debug_status', to: 'onboarding#debug_status'
  
  # Scout AI Assistant routes
  get 'scout', to: 'scout#index'
  post 'scout/chat', to: 'scout#chat'
  post 'scout/chat_stream', to: 'scout#chat_stream'
  post 'scout/chat_interactive', to: 'scout#chat_interactive'
  post 'scout/continue_workflow', to: 'scout#continue_workflow'
  get 'scout/history', to: 'scout#history' # paginated history
  delete 'scout/conversation', to: 'scout#clear_conversation'
  get 'scout/export', to: 'scout#conversation_export'
  get 'scout/conversations', to: 'scout#conversations'
  get 'scout/conversation/:session_id', to: 'scout#conversation'
  post 'scout/new_session', to: 'scout#new_session'
  
  # Scout Intelligent Canvas routes
  post 'scout/load_canvas', to: 'scout#load_canvas'
  get 'scout/available_canvases', to: 'scout#available_canvases'
  
  # OAuth integrations
  namespace :integrations do
    get ':integration_slug/auth', to: 'oauth#authorize', as: :oauth_authorize
    get 'callback/:slug', to: 'oauth#callback', as: :oauth_callback
  end
  
  # Webhook endpoints
  post 'webhooks/:integration_slug', to: 'webhooks#receive', as: :webhook_receive
  
  # Admin routes
  namespace :admin do
    get 'login', to: 'sessions#new', as: :new_session
    post 'login', to: 'sessions#create', as: :session
    delete 'logout', to: 'sessions#destroy', as: :destroy_session
    
    # Dashboard
    get '/', to: 'dashboard#index', as: :dashboard
    
    # Integrations management
    resources :integrations do
      collection do
        get :logs
      end
      resources :operations, controller: 'integration_operations'
    end
    
    # Connections management
    resources :connections do
      member do
        post :test
        post :refresh
      end
    end
    
    # Policy management
    resources :policy_rules
    
    # User management
    resources :users do
      member do
        post :make_admin
        post :revoke_admin
      end
    end
    
    # Admin user management
    resources :admin_users do
      member do
        post :unlock
      end
    end
    
    # Observability
    namespace :observability do
      get 'ai_usage', to: 'metrics#ai_usage'
      get 'workflows', to: 'metrics#workflows'
      get 'errors', to: 'metrics#errors'
      get 'performance', to: 'metrics#performance'
    end
  end

  # Common routes (regardless of subdomain)
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
