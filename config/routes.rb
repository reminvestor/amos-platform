require "solid_queue"

Rails.application.routes.draw do
  # Health check endpoints - must be first!
  get "up", to: "health#up"
  get "health", to: "health#index"
  get "health_check", to: "health#up"

  get "crawler_jobs/index"
  get "crawler_jobs/new"
  get "crawler_jobs/create"

  # Diagnostic route for SSL/headers issues
  get "debug_headers" => proc { |env|
    headers = env.select { |k, v| k.start_with?("HTTP_") || [ "HTTPS", "REQUEST_METHOD", "REQUEST_URI", "rack.url_scheme" ].include?(k) }
    [ 200, { "Content-Type" => "application/json" }, [ headers.to_json ] ]
  }

  # ActionCable for real-time features
  mount ActionCable.server => "/cable"

  # API routes
  namespace :api do
    # Voice Assistant API
    namespace :voice do
      resources :sessions, only: [:create, :show], controller: "voice_sessions", param: :id do
        member do
          get :deepgram_key
          get :eleven_labs_credentials
          patch :end
          post :log_error
        end
      end

      # Voice Health Monitoring
      namespace :health do
        get :status           # Overall health status
        get :providers        # Provider-specific status
        get :metrics          # Usage and performance metrics
        get :optimization     # Optimization recommendations
        post :prewarm         # Manually trigger pre-warming
      end
    end
    
    # Text-to-Speech API
    namespace :tts do
      post :synthesize
      get :voices
      post :presigned_url
      get :preferences, action: :preferences
      patch :preferences, action: :update_preferences
      get :test
    end

    # MCP Approval Client API (for development/testing)
    # Support both underscore and hyphen versions for compatibility
    post :request_approval, to: "approvals#request_approval"
    post "request-approval", to: "approvals#request_approval"
    post :get_instructions, to: "approvals#get_instructions"
    post "get-instructions", to: "approvals#get_instructions"

    namespace :v1 do
      # Health check endpoint
      get "health", to: "health#index"
      
      # Agent Auth / Heartbeat endpoints
      resources :agent_auth, only: [] do
        member do
          post :heartbeat
          get :current_task
        end
      end

      resources :contacts, only: [ :create ]
      resources :jobs, only: [ :show ]
      post "crawler_contacts", to: "crawler_contacts#create"

      # Crawler Job Logging
      post "crawler_jobs/:id/logs", to: "crawler_job_logs#create"

      # Landing page form submissions
      resources :landing_page_submissions, only: [ :create, :index, :show ] do
        member do
          post :process
          post :spam
        end
        collection do
          get :export
        end
      end
      # Alternative route for submissions by landing page slug
      post "landing_pages/:landing_page_slug/submit", to: "landing_page_submissions#create"
    end
  end

  # Devise routes for authentication - accessible from all subdomains (including none)
  devise_for :users, controllers: {
    registrations: "users/registrations",
    sessions: "users/sessions",
    passwords: "users/passwords"
  }

  # Routes with constraints on subdomain - application routes for 'app' or 'dev' subdomain
  constraints(lambda { |req|
    SubdomainConfig.app_subdomains.include?(req.subdomain)
  }) do
    # Solid Queue Interface
    authenticate :user, lambda { |u| u.admin? } do
      mount SolidQueueInterface::Engine => "/solid_queue"
    end

    # User management
    resources :users, only: [ :show, :edit, :update ]

    # Admin namespace
    namespace :admin do
      resources :imports, only: [ :index ] do
        collection do
          post :elearning
        end
      end

      resources :maintenance, only: [ :index ] do
        collection do
          post :add_missing_email_deliveries
          post :fix_campaign_entity_ids
          post :reprocess_drip_campaigns
        end
      end

      # Entity cost tracking
      resources :entity_costs, only: [ :index, :show ] do
        member do
          get :export
        end
        collection do
          get :bulk_analysis
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
    resources :image_assets, only: [ :index, :new, :create, :show, :destroy ] do
      collection do
        post :generate
      end
    end
    
    # Document store for RAG
    resources :documents do
      member do
        get :download
        post :add_tags
        post :assign_subjects
        post :retry_processing
      end
      collection do
        get :search
      end
    end
  
    # Document organization
    resources :document_subjects do
      member do
        post :move
      end
    end
    
    resources :document_tags do
      member do
        post :merge
      end
      collection do
        get :suggest
      end
    end
    
    resources :saved_searches do
      member do
        post :run
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

        get :analyze
        post :setup_drip
        post :trigger_drip
      end
    end

    resources :email_sequences do
      resources :sequence_steps
      member do
        post :activate
        post :pause
        post :enroll_group
      end
    end

    # Entity-level Agent & Tool Management
    resources :agent_plugins
    resources :tools
    
    # AI Settings (Scout configuration, Voice settings)
    namespace :ai_settings do
      resource :scout, only: [:show, :update], controller: 'scout'
      resource :voice, only: [:show, :update], controller: 'voice'
    end

    # Energy Dashboard (Agent Collaboration System)
    namespace :dashboard do
      resources :energy, only: [:index, :show] do
        collection do
          post :regenerate
          post :distribute_pool
        end
        member do
          post :enroll_in_school
        end
      end
    end

  # Landing pages
  # Agent system routes
  namespace :agents do
    resources :monitoring do
      collection do
        get :performance_metrics
        get :decision_traces
        get :collaboration_network
        get :learning_insights
        get :resource_usage
        get :alerts
        get :export_report
      end
      member do
        get :agent_details
      end
    end

    # Test routes (development only)
    if Rails.env.development?
      resources :test, only: [ :index ] do
        collection do
          post :create_agent
          post :plan_workflow
          post :execute_workflow
          post :test_parallel
          post :test_resilience
          post :test_learning
          post :agent_communication
          post :resource_usage
          post :performance_metrics
        end
      end
    end
  end

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
        post "rollback/:version_id", to: "landing_pages#rollback", as: :rollback
        get :clarify
        post :answer_clarification
      end
    end

    # Public landing page view (no auth required)
    get "landing/:slug", to: "landing_pages#public_view", as: :landing_page_public

    # AI content generation routes
    get "ai_content/new", to: "ai_content#new", as: :new_ai_content
    post "ai_content/generate", to: "ai_content#generate", as: :generate_ai_content
    get "ai_content/improve/:template_id", to: "ai_content#improve", as: :improve_ai_content
    post "ai_content/improve/:template_id", to: "ai_content#improve"
    get "ai_content/analyze_campaign/:campaign_id", to: "ai_content#analyze_campaign", as: :ai_analyze_campaign
    post "ai_content/reanalyze_campaign/:campaign_id", to: "ai_content#reanalyze_campaign", as: :reanalyze_campaign

    # Email tracking routes
    get "campaign_tracking/open/:id", to: "campaign_tracking#open", as: :email_open
    get "campaign_tracking/click/:id", to: "campaign_tracking#click", as: :email_click

    # Subscription management
    get "unsubscribe", to: "subscription#unsubscribe", as: :unsubscribe

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
    resource :business_profile, only: [ :edit, :update ] do
      member do
        post :add_knowledge
        patch :update_style_guidelines
      end
    end

    # Social media account management
    resources :social_media_accounts, only: [ :index, :new, :create ] do
      collection do
        get "auth/:platform", to: "social_media_accounts#new", as: :auth
        get "callback/:platform", to: "social_media_accounts#callback", as: :callback
        delete "disconnect/:id", to: "social_media_accounts#disconnect", as: :disconnect
      end
    end
    
    # Alias for integrations (points to social_media_accounts controller)
    get "integrations", to: "social_media_accounts#index", as: :customer_integrations

    # Crawler Jobs Management
    resources :crawler_jobs, only: [ :index, :new, :create, :show ] do
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

    # ========================================
    # Three Main Modes Under App Subdomain
    # ========================================

    # Root redirects to chat (default mode)
    root to: redirect("/chat"), as: :application_root

    # Chat Mode (AMOS AI Conversational Interface)
    get "/chat", to: "scout#index", as: :chat_mode

    # Advanced Mode (Traditional Dashboard with Sidebar)
    get "/advanced", to: "dashboard#index", as: :advanced_mode

    # Entity-level management (for entity owners/admins)
    namespace :entity do
      resources :users do
        member do
          post :change_role
        end
      end
      get "observability", to: "observability#index"

      resources :policies do
        member do
          post :toggle
        end
      end
      
      resource :privacy, only: [:show, :update], controller: 'privacy'
    end

    # Affiliate Program Routes (User-facing)
    namespace :affiliate do
      get 'apply', to: 'applications#new', as: :apply
      post 'apply', to: 'applications#create'
      get 'dashboard', to: 'dashboard#show', as: :dashboard
      resources :resources, only: [:index]
      resources :payouts, only: [:index]
      # Add standard resource routes for tests
      resources :applications, only: [:new, :create]
    end

    # Admin Portal (Platform Administration)
    # Note: /admin routes are defined below in the admin namespace

    # OAuth integrations (user-facing, inside app subdomain)
    namespace :integrations do
      get ":integration_slug/auth", to: "oauth#authorize", as: :oauth_authorize
      get "callback/:slug", to: "oauth#callback", as: :oauth_callback
    end
  end

  # Routes for marketing site (no subdomain or www subdomain)
  constraints(lambda { |req| !req.subdomain.present? || req.subdomain == 'www' }) do
    # Marketing site routes
    get '/', to: 'marketing#index', as: :marketing_root
    get '/features', to: 'marketing#features', as: :marketing_features
    get '/pricing', to: 'marketing#pricing', as: :marketing_pricing
    get '/about', to: 'marketing#about', as: :marketing_about
    get '/contact', to: 'marketing#contact', as: :marketing_contact
    post '/contact', to: 'marketing#contact_submit', as: :marketing_contact_submit
    get '/help', to: 'marketing#help', as: :marketing_help
    get '/terms', to: 'marketing#terms', as: :marketing_terms
    get '/privacy', to: 'marketing#privacy', as: :marketing_privacy
  end

  # Debug routes for troubleshooting
  get "debug", to: "debug#index"
  get "debug/status", to: "debug#status"
  get "debug/test_sse", to: "debug#test_sse"

  # Onboarding routes
  get "onboarding", to: "onboarding#index"
  post "onboarding/chat", to: "onboarding#chat"
  patch "onboarding/complete", to: "onboarding#complete"
  get "onboarding/reset", to: "onboarding#reset"
  get "onboarding/debug_status", to: "onboarding#debug_status"

  # Scout AI Assistant routes
  get "scout", to: "scout#index"
  post "scout/chat", to: "scout#chat"
  post "scout/chat_stream", to: "scout#chat_stream"
  post "scout/chat_interactive", to: "scout#chat_interactive"
  post "scout/continue_workflow", to: "scout#continue_workflow"
  post "scout/approve_workflow", to: "scout#approve_workflow"
  post "scout/task_statuses", to: "scout#task_statuses"
  post "scout/upload_files", to: "scout#upload_files"
  get "scout/history", to: "scout#history" # paginated history
  delete "scout/conversation", to: "scout#clear_conversation"
  get "scout/export", to: "scout#conversation_export"
  get "scout/conversations", to: "scout#conversations"
  get "scout/conversation/:session_id", to: "scout#conversation"
  post "scout/new_session", to: "scout#new_session"

  # Scout Intelligent Canvas routes
  post "scout/load_canvas", to: "scout#load_canvas"
  get "scout/available_canvases", to: "scout#available_canvases"
  post "scout/cancel_job", to: "scout#cancel_job"

  # Document indexing status API
  get "scout/document-status/:asset_id", to: "scout#document_indexing_status"

  # Analytics routes
  get "analytics", to: "analytics#index"
  get "analytics/stream", to: "analytics#stream"
  get "analytics/activity_feed", to: "analytics#activity_feed"
  get "analytics/engagement_heatmap", to: "analytics#engagement_heatmap"
  get "analytics/top_performers", to: "analytics#top_performers"

  # A/B Testing routes
  resources :ab_tests do
    member do
      post :start
      post :pause
      post :resume
      post :stop
      post :complete
    end
  end

  # Integration management
  resources :integrations, only: [ :index ]
  get "integrations/connect/:slug", to: "integrations#connect", as: :connect_integration
  post "integrations/connect/:slug", to: "integrations#create_connection", as: :create_connection_integration

  # User-facing connections actions
  resources :connections, only: [:destroy] do
    member do
      post :test
      get :operations
      patch :credentials, to: "connections#update_credentials"
    end
  end

  # Webhook endpoints
  post "webhooks/:integration_slug", to: "webhooks#receive", as: :webhook_receive

  # Subscription management (signup flow)
  resources :subscriptions, only: [:new, :create] do
    collection do
      get 'success'
      get 'cancel'
    end
  end

  # Stripe billing webhooks
  post 'stripe/webhooks', to: 'stripe_webhooks#create', as: :stripe_webhooks

  # Stripe checkout and billing
  namespace :stripe do
    post 'checkout', to: 'stripe_checkout#create', as: :checkout
    get 'checkout/success', to: 'stripe_checkout#success', as: :checkout_success
    get 'checkout/cancel', to: 'stripe_checkout#cancel', as: :checkout_cancel
    post 'portal', to: 'stripe_checkout#create_portal_session', as: :portal
  end

  # SES Webhooks
  post "/webhooks/ses", to: "ses_webhooks#create"

  # Admin routes
  namespace :admin do
    get "login", to: "sessions#new", as: :new_session
    post "login", to: "sessions#create", as: :session
    delete "logout", to: "sessions#destroy", as: :destroy_session

    # Dashboard
    get "/", to: "dashboard#index", as: :dashboard
    get "/services", to: "dashboard#services", as: :services

    # Observability
    get "/observability/ai_usage", to: "observability#ai_usage", as: :observability_ai_usage
    get "/observability/ai_usage/entity/:entity_id", to: "observability#ai_usage_by_entity", as: :observability_ai_usage_entity
    get "/observability/workflows", to: "observability#workflows", as: :observability_workflows
    get "/observability/performance", to: "observability#performance", as: :observability_performance
    get "/observability/errors", to: "observability#errors", as: :observability_errors

    # Scout session management (Redis history)
    resources :scout_sessions, only: [:index, :show, :destroy] do
      member do
        post :sync_redis
      end
    end

    # Affiliate Management
    resources :affiliates do
      collection do
        get :analytics
      end
      member do
        post :approve
        post :suspend
        patch :update_commission_rate
      end
    end

    # Affiliate Settings
    get "/settings/affiliate", to: "affiliates#settings", as: :settings_affiliate
    patch "/settings/affiliate", to: "affiliates#update_settings"

    resources :commissions do
      collection do
        post :bulk_approve
      end
      member do
        post :approve
        post :cancel
      end
    end

    resources :payouts do
      member do
        post :mark_completed
      end
    end

    namespace :settings do
      resource :affiliate, only: [:show, :update]
    end

    namespace :analytics do
      resources :affiliates, only: [:index]
    end

    # Integrations management
    resources :integrations do
      member do
        post :discover_operations
      end
      collection do
        get :logs
      end
      resources :operations, controller: "integration_operations"
      resources :oauth_configurations, except: [:index]
    end
    
    # OAuth Configurations management (standalone for listing all)
    resources :oauth_configurations, only: [:index]

    # Connections management
    resources :connections do
      member do
        post :test
        post :refresh
      end
    end

    # Bedrock Knowledge Base management
    resources :bedrock_kb, only: [:index, :show] do
      member do
        post :create_kb
        post :enable
        post :disable
        post :sync
      end
    end

    # AI Pipeline management
    resources :pipeline_connections do
      member do
        post :test
      end
    end

    resources :pipeline_executions, only: [:index, :show] do
      member do
        post :retry
        post :cancel
      end
    end

    # Policy management
    resources :policy_rules

    # User management
    resources :users do
      member do
        post :make_admin
        post :revoke_admin
        post :reset_password
      end
    end
    
    # Parallel task monitoring
    resources :parallel_tasks, only: [:index, :show] do
      member do
        post :cancel
        post :retry
      end
    end

    # Admin user management
    resources :admin_users do
      member do
        post :unlock
      end
    end

    # System settings
    resources :system_settings, only: [:index, :update] do
      collection do
        post :reset_defaults
        patch :update_all
      end
    end

    # Observability
    namespace :observability do
      get "ai_usage", to: "metrics#ai_usage"
      get "workflows", to: "metrics#workflows"
      get "errors", to: "metrics#errors"
      get "performance", to: "metrics#performance"
    end

    # Agent Collaboration System Dashboard (replaces Agent Lightning)
    resources :agent_collaboration, only: [] do
      collection do
        get :dashboard, as: :dashboard
        get :agents, as: :agents
        get :school, as: :school
        get :collaborations, as: :collaborations
        get :ab_tests, as: :ab_tests
        get :transactions, as: :transactions
        post :regenerate_all, as: :regenerate_all
        post :distribute_pools, as: :distribute_pools
        post :recalibrate_capabilities, as: :recalibrate_capabilities
        post :update_boundaries, as: :update_boundaries
      end
      member do
        get :agent_detail, as: :agent_detail
        post :enroll_agent, as: :enroll_agent
        post :cancel_test, as: :cancel_test
      end
    end

    # Agent Plugins Management
    resources :agent_plugins do
      member do
        post :activate
        post :deactivate
        post :publish
        post :unpublish
        get :test
        post :run_test
        post :clone
      end
      collection do
        get :analytics
        post :purge_executions
      end
    end

    # Tools Management
    resources :tools do
      member do
        post :publish
        post :unpublish
        post :clone
      end
    end
  end

  # Common routes (regardless of subdomain)
  # Amos Integration - needs to be accessible from any subdomain for agent callbacks
  post "amos/callback/:session_id", to: "amos#callback", as: :amos_callback
  
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Mount LetterOpenerWeb in development
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  # Default root path for tests and unauthenticated users (only applies when no other root is defined)
  # root to: redirect("/chat")
end
