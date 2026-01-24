require "solid_queue"

Rails.application.routes.draw do
  # Health check endpoints - must be first!
  get "up", to: "health#up"
  get "health", to: "health#index"
  get "health_check", to: "health#up"

  # Landing page subdomain routes
  # The SubdomainRouter middleware rewrites *.lp.{domain} requests to /lp/:subdomain
  get "/lp/:subdomain", to: "lp#show", as: :landing_page_subdomain

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
    # Mobile App Authentication
    post 'auth/login', to: 'auth#login'
    post 'auth/verify-mfa', to: 'auth#verify_mfa'
    post 'auth/register', to: 'auth#register'
    post 'auth/logout', to: 'auth#logout'
    get 'auth/me', to: 'auth#me'
    post 'auth/refresh_token', to: 'auth#refresh_token'
    post 'auth/regenerate_api_key', to: 'auth#regenerate_api_key'

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
    
    # MFA API
    scope :mfa do
      get :status, to: 'mfa#status'
      post :enable, to: 'mfa#enable'
      post :confirm, to: 'mfa#confirm'
      delete :disable, to: 'mfa#disable'
      post :regenerate_backup_codes, to: 'mfa#regenerate_backup_codes'
    end

    # Business Profile API
    resource :business_profile, only: [:show, :update], controller: 'business_profiles'

    # Work Items API
    resources :work_items, only: [] do
      member do
        get :content
        post :toggle_star
        post :archive
        post :mark_read
        post :mark_unread
        post :respond, action: :respond_to_input
        post :skip_input
        post :save_to_documents
      end
    end
    
    # Module Webhooks API (Extensible Module System)
    post 'webhooks/modules/:slug', to: 'module_webhooks#receive', as: :module_webhook

    # Module Data API (CRUD for dynamic models)
    scope 'modules/:module_slug' do
      get 'stats', to: 'module_data#stats'
      get 'models/:model_name/schema', to: 'module_data#schema'
      get 'models/:model_name', to: 'module_data#index'
      post 'models/:model_name', to: 'module_data#create'
      get 'models/:model_name/:id', to: 'module_data#show'
      patch 'models/:model_name/:id', to: 'module_data#update'
      put 'models/:model_name/:id', to: 'module_data#update'
      delete 'models/:model_name/:id', to: 'module_data#destroy'
    end

    # Support Tickets API
    resources :support_tickets, only: [:create]
    
    # Image Assets API (Media Library)
    resources :image_assets, only: [:index, :show, :create, :destroy] do
      member do
        post :toggle_sharing
      end
      collection do
        post :generate  # AI image generation with Nano Banana
      end
    end

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
      resources :contacts_list, only: [ :index, :show, :create, :update, :destroy ], path: 'contacts_list'
      resources :campaigns, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :pause
          post :resume
          post :send_now
          post :schedule
          post :send_test
          post :stop
        end
      end
      resources :landing_pages, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :publish
          post :unpublish
        end
      end

      # Analytics for mobile app
      resources :analytics, only: [] do
        collection do
          get :dashboard
          get :campaigns
          get :landing_pages
        end
      end

      # Chat history for mobile app
      scope :chat, as: 'chat' do
        get 'history', to: 'chat#history'
        get 'conversations', to: 'chat#conversations'
        delete 'clear', to: 'chat#clear'
      end

      # Connections for mobile app
      resources :connections, only: [ :index, :show, :destroy ] do
        member do
          post :test
        end
        collection do
          get :available
        end
      end

      # Email templates for mobile app
      resources :email_templates, only: [ :index, :show, :create, :update, :destroy ]

      # Contact groups for mobile app
      resources :contact_groups, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :add_contacts
          post :remove_contacts
        end
      end

      # Documents/RAG for mobile app
      resources :documents, only: [ :index, :show, :create, :destroy ] do
        collection do
          get :collections
        end
        member do
          get :status
        end
      end

      resources :jobs, only: [ :show ]
      post "crawler_contacts", to: "crawler_contacts#create"

      # Crawler Job Logging
      post "crawler_jobs/:id/logs", to: "crawler_job_logs#create"

      # Custom Agents API
      resources :agents, only: [ :index, :show ] do
        member do
          post :execute
        end
        collection do
          get :agent_types
        end
      end

      # Landing page form submissions
      resources :landing_page_submissions, only: [ :create, :index, :show ] do
        member do
          post :mark_processed
          post :spam
        end
        collection do
          get :export
        end
      end
      # Alternative route for submissions by landing page slug
      post "landing_pages/:landing_page_slug/submit", to: "landing_page_submissions#create"

      # Benchmark API
      resources :benchmarks, only: [:index, :show] do
        collection do
          get :report
          get :trends
          get :comparison
          post :run
        end
      end

      # Notifications for mobile app
      resources :notifications, only: [:index, :show] do
        member do
          post :mark_read
          post :dismiss
        end
        collection do
          get :unread_count
          post :mark_all_read
        end
      end

      # Tasks for mobile app
      resources :tasks, only: [:index, :show, :create, :update, :destroy]

      # Team management for mobile app
      namespace :team do
        get '/', action: :members, as: :members
        post :invite
        delete 'invite/:id', action: :cancel_invite, as: :cancel_invite
        post 'invite/:id/resend', action: :resend_invite, as: :resend_invite
        patch 'members/:id', action: :update_member, as: :update_member
        delete 'members/:id', action: :remove_member, as: :remove_member
      end

      # Work items (inbox) for mobile app
      resources :work_items, only: [:index, :show] do
        member do
          post :mark_read
          post :toggle_starred
          post :archive
          post :unarchive
        end
        collection do
          post :mark_all_read
        end
      end

      # Scheduled tasks for mobile app
      resources :scheduled_tasks, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :pause
          post :resume
          post :run_now
        end
        collection do
          get :task_types
        end
      end

      # CRM - Opportunities
      resources :opportunities do
        member do
          post :move_stage
          post :assign
          post :close_won
          post :close_lost
          post :reopen
        end
        collection do
          get :pipeline
          post :reorder
        end
      end

      # CRM - Activities
      resources :activities do
        member do
          post :complete
          post :cancel
          post :assign
          post :reschedule
        end
        collection do
          get :tasks
          get :timeline
          post :log_note
          post :log_call
          post :log_email
          post :create_task
          post :schedule_meeting
        end
      end

      # User Feedbacks for mobile app
      resources :feedbacks, only: [:index, :create, :destroy] do
        collection do
          get :stats
        end
      end
      get "feedbacks/agent/:agent_id", to: "feedbacks#agent_feedback", as: :agent_feedbacks
    end
  end

  # Devise routes for authentication - accessible from all subdomains (including none)
  devise_for :users, controllers: {
    registrations: "users/registrations",
    sessions: "users/sessions",
    passwords: "users/passwords",
    omniauth_callbacks: "users/omniauth_callbacks"
  }

  # MFA verification during login (outside app subdomain for login flow)
  devise_scope :user do
    get "users/sessions/verify_otp", to: "users/sessions#verify_otp", as: :verify_otp_user_session
    post "users/sessions/verify_otp", to: "users/sessions#submit_otp"
    post "users/sessions/send_email_otp", to: "users/sessions#send_email_otp"
    post "users/sessions/use_backup_code", to: "users/sessions#use_backup_code"
  end

  # Legal pages (terms and privacy) - accessible without login
  get "terms", to: "legal#terms", as: :terms_of_service
  get "privacy", to: "legal#privacy", as: :privacy_policy
  get "accept-terms", to: "legal#accept_terms", as: :accept_terms
  post "accept-terms", to: "legal#submit_terms"

  # Routes with constraints on subdomain - application routes for 'app' or 'dev' subdomain
  constraints(lambda { |req|
    SubdomainConfig.app_subdomains.include?(req.subdomain)
  }) do
    # Solid Queue Interface
    authenticate :user, lambda { |u| u.admin? } do
      mount SolidQueueInterface::Engine => "/solid_queue"
    end

    # Two-Factor Authentication (MFA) - must be before resources :users to avoid being matched as user id
    namespace :users do
      resource :two_factor, only: [:show], controller: 'two_factor' do
        get :enable
        post :confirm
        delete :disable
        get :backup_codes
        post :regenerate_backup_codes
        get :email_settings
        patch :email_settings, action: :update_email_settings
      end
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
    resources :contacts do
      collection do
        post :import
      end
    end
    resources :contact_groups do
      collection do
        get :search_contacts
      end
      member do
        post :upload_csv
      end
    end

    # CRM / Sales
    resources :opportunities do
      member do
        post :move_stage
        post :close_won
        post :close_lost
      end
    end
    resources :activities do
      member do
        post :complete
      end
      collection do
        get :tasks
      end
    end

    # Media library
    resources :image_assets, only: [ :index, :new, :create, :show, :destroy ] do
      member do
        post :toggle_sharing
      end
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

    # User referral program (not affiliate program)
    resources :referrals, only: [:index, :create]

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
    
    # User-facing Scheduled Tasks Management
    resources :scheduled_tasks do
      member do
        post :pause
        post :resume
        post :run_now
        post :reset_failures
        get :runs
      end
      collection do
        post :api_create
      end
    end
    # API endpoints for scheduled tasks (canvas form saves)
    post 'scheduled_tasks/:id/api_update', to: 'scheduled_tasks#api_update', as: :api_update_scheduled_task
    delete 'scheduled_tasks/:id/api_destroy', to: 'scheduled_tasks#api_destroy', as: :api_destroy_scheduled_task
    
    # Billing & Work Tokens (user-facing)
    resource :billing, only: [:show], controller: 'billing' do
      get '/', action: :index, as: ''
      get :settings
      patch :settings, action: :update_settings
      get :purchase
      post :purchase, action: :create_purchase
      get :setup_payment
      post :confirm_payment_method
      delete :remove_payment_method
      get :transactions
      get :usage
      get :invoices
      get 'receipt/:id', action: :receipt, as: :receipt
    end
    
    # AI Settings (Scout configuration, Voice settings, Menu configuration)
    namespace :ai_settings do
      resource :scout, only: [:show, :update], controller: 'scout'
      resource :voice, only: [:show, :update], controller: 'voice'
      resource :menu, only: [:show, :update], controller: 'menu' do
        post :toggle, on: :collection, as: :toggle
        post :reset, on: :collection
      end
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

  # Extensible Module System routes (Apps)
  resources :app_modules, path: 'modules', controller: 'modules', param: :slug, except: [:new, :edit] do
    member do
      post :activate
      post :deactivate
      get :canvases
      post :export
      post :share      # Share module with team (user_private → entity_shared)
      post :unshare    # Make module private again (entity_shared → user_private)
    end
    collection do
      get :installed
      get :templates
      post :install_template
      post :import
    end
  end
  
  # Module canvas loading
  get 'modules/:slug/canvas/:canvas_slug', to: 'modules#load_canvas', as: :module_canvas

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

  # Personal Space - Bookmarks
  resources :bookmarks do
    member do
      patch :share
      patch :unshare
    end
  end

  # Personal Space - Notes
  resources :notes, except: [:show] do
    member do
      patch :toggle_pin
      patch :archive
      patch :unarchive
    end
    collection do
      get :archived
    end
  end

  # Personal Space - Reminders
  resources :reminders, except: [:show] do
    member do
      patch :complete
      patch :uncomplete
    end
    collection do
      get :completed
    end
  end

  # Team Space - Channels
  resources :channels do
    member do
      patch :archive
      patch :unarchive
    end
    collection do
      get :completed
    end
  end

    # Public landing page view (no auth required)
    get "landing/:slug", to: "landing_pages#public_view", as: :landing_page_public
    
    # Team invites (public routes)
    get "invite/:token", to: "team_invites#show", as: :accept_team_invite
    post "invite/:token/accept", to: "team_invites#accept", as: :confirm_team_invite
    post "invite/:token/decline", to: "team_invites#decline", as: :decline_team_invite

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
        collection do
          get :new_invite
          post :create_invite
          post :toggle_shared_pool
        end
        member do
          post :change_role
          get :edit_membership
          patch :update_membership
          delete :remove_member
          post :resend_invite
          delete :cancel_invite
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
      get ":integration_slug/params", to: "oauth#params_form", as: :oauth_params_form
      post ":integration_slug/params", to: "oauth#submit_params", as: :oauth_submit_params
      get "callback/:slug", to: "oauth#callback", as: :oauth_callback
    end
  end

  # Marketing site moved to external service - redirect root to app login
  constraints(lambda { |req| !req.subdomain.present? || req.subdomain == 'www' }) do
    get '/', to: redirect('/users/sign_in')
  end

  # Debug routes for troubleshooting
  get "debug", to: "debug#index"
  get "debug/status", to: "debug#status"
  get "debug/test_sse", to: "debug#test_sse"

  # Onboarding Wizard (default - step-by-step)
  get "onboarding", to: "onboarding_wizard#show", as: :onboarding
  patch "onboarding", to: "onboarding_wizard#update"
  post "onboarding/skip", to: "onboarding_wizard#skip", as: :onboarding_skip
  
  # Legacy onboarding routes (conversational - deprecated)
  get "onboarding/legacy", to: "onboarding#index", as: :onboarding_legacy
  post "onboarding/legacy/chat", to: "onboarding#chat"
  patch "onboarding/legacy/complete", to: "onboarding#complete"
  get "onboarding/legacy/reset", to: "onboarding#reset"
  get "onboarding/debug_status", to: "onboarding#debug_status"
  
  # Keep wizard alias for backwards compatibility
  get "onboarding/wizard", to: redirect("/onboarding")
  patch "onboarding/wizard", to: redirect("/onboarding")

  # Scout AI Assistant routes (legacy - keeping for backward compatibility)
  get "scout", to: "scout#index"
  post "scout/chat", to: "scout#chat"
  post "scout/chat_stream", to: "scout#chat_stream"
  post "scout/chat_interactive", to: "scout#chat_interactive"
  post "scout/continue_workflow", to: "scout#continue_workflow"
  post "scout/approve_workflow", to: "scout#approve_workflow"
  post "scout/approve_plan", to: "scout#approve_plan"
  post "scout/task_statuses", to: "scout#task_statuses"
  post "scout/upload_files", to: "scout#upload_files"
  get "scout/history", to: "scout#history" # paginated history
  delete "scout/conversation", to: "scout#clear_conversation"
  get "scout/export", to: "scout#conversation_export"
  get "scout/conversations", to: "scout#conversations"
  get "scout/conversation/:session_id", to: "scout#conversation"
  post "scout/new_session", to: "scout#new_session"
  post "scout/fresh_start", to: "scout#fresh_start"
  post "scout/switch_space", to: "scout#switch_space"
  get "scout/search_history", to: "scout#search_history"
  get "scout/agent_questions", to: "scout#agent_questions"
  post "scout/answer_agent_question", to: "scout#answer_agent_question"
  post "scout/skip_agent_question", to: "scout#skip_agent_question"
  get "scout/bookmarks", to: "scout#bookmarks"
  get "scout/bookmarks/:id", to: "scout#show_bookmark"
  post "scout/save_visualization", to: "scout#save_visualization"
  
  # Model selection mode routes
  post "scout/set_model_mode", to: "scout#set_model_mode"
  get "scout/model_mode", to: "scout#get_model_mode"

  # Scout Intelligent Canvas routes
  post "scout/load_canvas", to: "scout#load_canvas"
  get "scout/available_canvases", to: "scout#available_canvases"
  get "scout/workflow_items", to: "scout#workflow_items"
  get "scout/load_workflow", to: "scout#load_workflow"
  post "scout/save_workflow", to: "scout#save_workflow"
  get "scout/workflow_node_registry", to: "scout#workflow_node_registry"
  get "scout/workflow_items", to: "scout#workflow_items"
  post "scout/compile_workflow", to: "scout#compile_workflow"
  post "scout/test_workflow", to: "scout#test_workflow"

  # Workflow webhooks - external services can trigger workflows
  post "webhooks/workflow/:path", to: "webhooks/workflows#receive", as: :workflow_webhook
  post "scout/cancel_job", to: "scout#cancel_job"
  post "scout/capture_web_page", to: "scout#capture_web_page"
  get "scout/browser_session_screenshot/:session_id", to: "scout#browser_session_screenshot"
  post "scout/browser_session_sync_proxy", to: "scout#browser_session_sync_proxy"
  post "scout/browser_session_screenshot_refresh", to: "scout#browser_session_screenshot_refresh"
  post "scout/browser_session_close", to: "scout#browser_session_close"

  # Amos AI Assistant routes (new naming - aliases for scout routes)
  get "amos", to: "scout#index"
  post "amos/chat", to: "scout#chat"
  post "amos/chat_stream", to: "scout#chat_stream"
  post "amos/chat_interactive", to: "scout#chat_interactive"
  post "amos/continue_workflow", to: "scout#continue_workflow"
  post "amos/approve_workflow", to: "scout#approve_workflow"
  get "amos/workflow_items", to: "scout#workflow_items"
  get "amos/load_workflow", to: "scout#load_workflow"
  post "amos/save_workflow", to: "scout#save_workflow"
  post "amos/task_statuses", to: "scout#task_statuses"
  post "amos/upload_files", to: "scout#upload_files"
  get "amos/history", to: "scout#history"
  delete "amos/conversation", to: "scout#clear_conversation"
  get "amos/export", to: "scout#conversation_export"
  get "amos/conversations", to: "scout#conversations"
  get "amos/conversation/:session_id", to: "scout#conversation"
  post "amos/new_session", to: "scout#new_session"
  post "amos/fresh_start", to: "scout#fresh_start"
  post "amos/switch_space", to: "scout#switch_space"
  get "amos/bookmarks", to: "scout#bookmarks"
  get "amos/bookmarks/:id", to: "scout#show_bookmark"
  post "amos/load_canvas", to: "scout#load_canvas"
  get "amos/available_canvases", to: "scout#available_canvases"
  post "amos/cancel_job", to: "scout#cancel_job"
  post "amos/capture_web_page", to: "scout#capture_web_page"
  get "amos/browser_session_screenshot/:session_id", to: "scout#browser_session_screenshot"
  post "amos/browser_session_sync_proxy", to: "scout#browser_session_sync_proxy"
  post "amos/browser_session_screenshot_refresh", to: "scout#browser_session_screenshot_refresh"
  post "amos/browser_session_close", to: "scout#browser_session_close"
  get "amos/document-status/:asset_id", to: "scout#document_indexing_status"
  get "amos/questions/pending", to: "scout/questions#pending"
  post "amos/questions/:id/answer", to: "scout/questions#answer"
  post "amos/questions/:id/skip", to: "scout/questions#skip"
  post "amos/feedback", to: "scout/feedbacks#create"
  get "amos/favorites", to: "scout/favorites#index"
  post "amos/favorites/toggle", to: "scout/favorites#toggle"
  get "amos/favorites/check", to: "scout/favorites#check"
  patch "amos/favorites/:id", to: "scout/favorites#update"
  delete "amos/favorites/:id", to: "scout/favorites#destroy"
  get "amos/work_items", to: "scout/work_items#index"
  get "amos/work_items/unread_count", to: "scout/work_items#unread_count"
  get "amos/work_items/:id", to: "scout/work_items#show"
  post "amos/work_items/:id/mark_read", to: "scout/work_items#mark_read"
  post "amos/work_items/:id/mark_unread", to: "scout/work_items#mark_unread"
  post "amos/work_items/:id/toggle_star", to: "scout/work_items#toggle_star"
  post "amos/work_items/:id/archive", to: "scout/work_items#archive"
  post "amos/work_items/mark_all_read", to: "scout/work_items#mark_all_read"

  # Web proxy for interactive browsing (strips X-Frame-Options to allow embedding)
  # Must accept non-GET requests for form submits / XHR in interactive mode.
  match "web_proxy", to: "web_proxy#proxy", via: :all

  # Catch-all for Next.js/_next paths that bypass the main proxy (dynamic chunks)
  # format: false ensures file extensions like .js, .woff2 are part of the path, not parsed as format
  get "_next/*path", to: "web_proxy#next_proxy", format: false

  # Block service worker registration attempts from proxied sites
  get "service-worker.js", to: "web_proxy#service_worker_stub"
  get "sw.js", to: "web_proxy#service_worker_stub"

  # Catch-all for ESPN-style paths (watch, sports sections, etc.)
  # These paths should be proxied to the original site stored in session
  get "watch/*path", to: "web_proxy#generic_proxy", format: false
  get "espn/*path", to: "web_proxy#generic_proxy", format: false

  # Block Akamai tracking pixels (return transparent gif to reduce console noise)
  get "akam/*path", to: "web_proxy#tracking_pixel", format: false

  # Block common error/tracking endpoints
  get "error/e.gif", to: "web_proxy#tracking_pixel"

  # Scout Feedback (session-based auth for in-app feedback)
  post "scout/feedback", to: "scout/feedbacks#create"

  # Scout Favorites (session-based auth for in-app favorites)
  get "scout/favorites", to: "scout/favorites#index"
  post "scout/favorites/toggle", to: "scout/favorites#toggle"
  get "scout/favorites/check", to: "scout/favorites#check"
  patch "scout/favorites/:id", to: "scout/favorites#update"
  delete "scout/favorites/:id", to: "scout/favorites#destroy"

  # Scout Question Queue (async agent questions)
  get "scout/questions/pending", to: "scout/questions#pending"
  post "scout/questions/:id/answer", to: "scout/questions#answer"
  post "scout/questions/:id/skip", to: "scout/questions#skip"

  # Internal callbacks for worker-to-web broadcasts (bypasses ActionCable cross-process issues)
  post "scout/broadcast_question", to: "scout/questions#broadcast_question"
  post "scout/broadcast_completion", to: "scout/questions#broadcast_completion"

  # Scout Work Items (agent completion results)
  get "scout/work_items", to: "scout/work_items#index"
  get "scout/work_items/unread_count", to: "scout/work_items#unread_count"
  get "scout/work_items/:id", to: "scout/work_items#show"
  post "scout/work_items/:id/mark_read", to: "scout/work_items#mark_read"
  post "scout/work_items/:id/mark_unread", to: "scout/work_items#mark_unread"
  post "scout/work_items/:id/toggle_star", to: "scout/work_items#toggle_star"
  post "scout/work_items/:id/archive", to: "scout/work_items#archive"
  post "scout/work_items/mark_all_read", to: "scout/work_items#mark_all_read"

  # ============================================
  # Hub - Collaborative Intelligence Hub
  # Where humans and AI agents communicate and collaborate
  # ============================================
  get "hub", to: "hub#index"
  
  # Thread management
  get "hub/thread/:id", to: "hub#show_thread", as: :hub_thread
  post "hub/thread/:id/messages", to: "hub#send_message"
  post "hub/thread/:id/mark_read", to: "hub#mark_read"
  post "hub/thread/:id/fresh_start", to: "hub#fresh_start"
  
  # System Notifications
  get "notifications", to: "notifications#index"
  get "notifications/unread_count", to: "notifications#unread_count"
  get "notifications/stats", to: "notifications#stats"
  post "notifications/mark_read", to: "notifications#mark_read"
  post "notifications/mark_all_read", to: "notifications#mark_all_read"
  post "notifications/dismiss", to: "notifications#dismiss"
  
  # Channels
  get "hub/channels", to: "hub#channels"
  get "hub/channel/:id", to: "hub#show_channel", as: :hub_channel
  post "hub/channels", to: "hub#create_channel"
  delete "hub/channels/:id", to: "hub#delete_channel"
  get "hub/channels/:id/messages", to: "hub#channel_messages"
  post "hub/channels/:id/messages", to: "hub#send_channel_message"
  
  # Direct Messages
  get "hub/dms", to: "hub#dms"
  post "hub/dms", to: "hub#create_dm"
  
  # Agents & Activity
  get "hub/agents", to: "hub#agents"
  get "hub/activity", to: "hub#activity"
  
  # Presence
  get "hub/presence", to: "hub#presence"
  post "hub/presence", to: "hub#update_presence"
  post "hub/heartbeat", to: "hub#heartbeat"
  
  # Message actions
  post "hub/messages/:id/react", to: "hub#add_reaction"
  delete "hub/messages/:id/react", to: "hub#remove_reaction"
  post "hub/messages/:id/respond", to: "hub#respond_to_message"
  post "hub/messages/:id/handoff_action", to: "hub#handoff_action"

  # Giphy integration
  get "hub/giphy/search", to: "hub#giphy_search"
  
  # Mention autocomplete
  get "hub/thread/:id/participants", to: "hub#thread_participants"
  get "hub/channels/:id/participants", to: "hub#channel_participants"

  # Document indexing status API
  get "scout/document-status/:asset_id", to: "scout#document_indexing_status"

  # Scout Agent Questions (for mobile app real-time updates)
  get "scout/questions/pending", to: "scout/questions#pending"
  post "scout/questions/:id/answer", to: "scout/questions#answer"
  post "scout/questions/:id/skip", to: "scout/questions#skip"
  post "scout/broadcast_question", to: "scout/questions#broadcast_question"
  post "scout/broadcast_completion", to: "scout/questions#broadcast_completion"

  # ============================================
  # Design Preview - iFrame previews for Design Space
  # ============================================
  get "design_preview/web_app/:id", to: "design_preview#web_app", as: :design_preview_web_app
  get "design_preview/website/:id", to: "design_preview#website", as: :design_preview_website
  get "design_preview/landing_page/:id", to: "design_preview#landing_page", as: :design_preview_landing_page
  get "design_preview/component", to: "design_preview#component", as: :design_preview_component
  get "design_preview/module/:slug", to: "design_preview#app_module", as: :design_preview_module
  get "design_preview/automation/:id", to: "design_preview#automation", as: :design_preview_automation

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
  
  # QuickBooks Webhooks
  post "/webhooks/quickbooks/disconnect", to: "webhooks/quickbooks#disconnect"
  post "/webhooks/quickbooks/notifications", to: "webhooks/quickbooks#notifications"

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
      resources :integration_actions do
        member do
          post :activate
          post :test
        end
        collection do
          post :generate
          post :generate_all
        end
      end
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

    # AI Rulesets management (behavioral constraints for Scout AI)
    resources :ai_rulesets do
      member do
        patch :toggle
        post :clone
      end
    end

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

    # Benchmark System
    resources :benchmarks, only: [:index, :show, :create] do
      collection do
        get :trends
        post :cleanup
        get 'status/:run_id', action: :status, as: :status
      end
      member do
        get :compare
      end
    end

    # Agent Collaboration System Dashboard (macro-level training)
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

    # Agent Lightning - Micro-level RL-based agent optimization
    resource :agent_lightning, only: [], controller: 'agent_lightning' do
      get '/', action: :dashboard, as: ''
      get :training_jobs
      get :optimizations
      get :traces
      get 'agent/:agent_id', action: :agent_detail, as: :agent_detail
      post :start_training
      post :stop_training
      post 'rollback/:optimization_id', action: :rollback, as: :rollback
      get :service_status
    end

    # Scheduled Tasks Management
    resources :scheduled_tasks do
      member do
        post :pause
        post :resume
        post :run_now
      end
      collection do
        get :runs
      end
    end

    # Billing & Work Tokens Management
    resources :billing, only: [:index, :edit, :update] do
      collection do
        get :accounts
        get :transactions
        get :revenue_report
        get :usage_report
      end
    end
    
    # User billing account management (nested under billing)
    get 'billing/accounts/:id', to: 'billing#account_detail', as: :billing_account_detail
    post 'billing/accounts/:id/credit', to: 'billing#credit_tokens', as: :billing_credit_tokens
    post 'billing/accounts/:id/suspend', to: 'billing#suspend_account', as: :billing_suspend_account
    post 'billing/accounts/:id/reactivate', to: 'billing#reactivate_account', as: :billing_reactivate_account
    post 'billing/accounts/:id/retry_replenishment', to: 'billing#retry_replenishment', as: :billing_retry_replenishment

    # Entity billing account management
    get 'billing/entity_accounts', to: 'billing#entity_accounts', as: :billing_entity_accounts
    get 'billing/entity_accounts/:id', to: 'billing#entity_account_detail', as: :billing_entity_account_detail
    post 'billing/entity_accounts/:id/credit', to: 'billing#credit_entity_tokens', as: :billing_credit_entity_tokens
    post 'billing/entity_accounts/:id/suspend', to: 'billing#suspend_entity_account', as: :billing_suspend_entity_account
    post 'billing/entity_accounts/:id/reactivate', to: 'billing#reactivate_entity_account', as: :billing_reactivate_entity_account

    # Agent Plugins Management (also serves as Loadout definitions)
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

    # Loadouts Management (Plugin Injection System)
    resources :loadouts, only: [:index, :show] do
      member do
        get :metrics
        post :apply_fix
      end
      collection do
        post :health_check
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

    # Living Platform - Autonomous Evolution Dashboard
    resources :living_platform, only: [:index, :show] do
      member do
        get :perception
        get :goals
        get :reflections
        get :cycles
        get :lifecycle
        post :run_perception
        post :run_desire_engine
        post :run_evolution
        post :run_benchmark
        post 'resolve_anomaly/:anomaly_id', action: :resolve_anomaly, as: :resolve_anomaly
        post 'cancel_goal/:goal_id', action: :cancel_goal, as: :cancel_goal
      end
      collection do
        get :benchmark_results
      end
    end

    # Context Graph - Decision Tracing & Precedent System
    resource :context_graph, only: [], controller: 'context_graph' do
      get '/', action: :index, as: ''
      get 'entity/:entity_id', action: :entity, as: :entity
      get :decisions
      get 'decision/:id', action: :show_decision, as: :decision
      get :precedents
      get :exceptions
      get :approvals
      get :stats
      post 'approve/:id', action: :approve, as: :approve
      post 'reject/:id', action: :reject, as: :reject
    end

    # Platform Evolution Engine - Self-Healing & Auto-Improvement
    resource :platform_evolution, only: [], controller: 'platform_evolution' do
      get '/', action: :index, as: ''
      get :tickets
      get :feature_requests
      get 'ticket/:id', action: :show_ticket, as: :ticket
      post 'ticket/:id/debug', action: :debug_ticket, as: :debug_ticket
      post 'ticket/:id/approve_feature', action: :approve_feature, as: :approve_feature
      post 'ticket/:id/reject_feature', action: :reject_feature, as: :reject_feature
      get :debug_sessions
      get 'debug_session/:id', action: :show_debug_session, as: :debug_session
      post 'debug_session/:id/retry', action: :retry_debug_session, as: :retry_debug_session
      post 'debug_session/:id/mark_failed', action: :mark_session_failed, as: :mark_session_failed
      get :code_fixes
      get 'code_fix/:id', action: :show_code_fix, as: :code_fix
      post 'code_fix/:id/approve', action: :approve_fix, as: :approve_fix
      post 'code_fix/:id/reject', action: :reject_fix, as: :reject_fix
      get :pull_requests
      get 'pull_request/:id', action: :show_pull_request, as: :pull_request
      post 'pull_request/:id/merge', action: :merge_pr, as: :merge_pr
      get :error_logs
      post :run_log_scan
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
