class Entity < ApplicationRecord
  # Validations
  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: %w[active inactive archived] }

  # Callbacks
  after_create :create_default_policies

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :inactive, -> { where(status: 'inactive') }
  scope :archived, -> { where(status: 'archived') }

  # Relationships with users through join table
  has_many :entity_users, dependent: :destroy
  has_many :users, through: :entity_users
  has_many :team_invites, dependent: :destroy
  has_many :team_channels, dependent: :destroy

  # Hub (Collaborative Intelligence) Associations
  has_many :hub_threads, dependent: :destroy
  has_many :hub_presences, dependent: :destroy
  
  # Shared billing account for team token pool
  has_one :entity_billing_account, dependent: :destroy

  # Integration relationships
  has_many :connections, dependent: :destroy
  has_many :integrations, through: :connections
  has_many :policy_rules, dependent: :destroy

  # Direct relationships with main resources
  has_many :contacts, dependent: :destroy
  has_many :contact_groups, dependent: :destroy
  has_many :opportunities, dependent: :destroy
  has_many :activities, dependent: :destroy
  has_many :email_templates, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  
  # Document management
  has_many :document_subjects, dependent: :destroy
  has_many :document_tags, dependent: :destroy
  has_many :saved_searches, dependent: :destroy
  has_many :landing_pages, dependent: :destroy
  has_many :websites, dependent: :destroy
  has_many :web_apps, dependent: :destroy
  has_many :custom_domains, dependent: :destroy
  has_many :design_plans, dependent: :destroy
  has_many :automation_codes, dependent: :destroy
  has_many :social_posts, dependent: :destroy
  has_many :social_media_accounts, dependent: :destroy
  has_many :business_profiles, dependent: :destroy
  has_many :crawler_jobs, dependent: :destroy
  has_many :image_assets, dependent: :destroy

  # AI Pipeline relationships
  has_many :mcp_connections, dependent: :destroy
  has_many :pipeline_executions, dependent: :destroy

  # Email sequence relationships
  has_many :email_sequences, dependent: :destroy
  has_many :sequence_enrollments, dependent: :destroy

  # Scout configuration
  has_one :scout_loadout_configuration, dependent: :destroy

  # Scout AI Associations
  has_many :scout_conversations, dependent: :destroy
  has_many :business_insights, dependent: :destroy

  # RAG Storage Associations
  has_many :rag_stores, dependent: :destroy
  has_many :rag_documents, through: :rag_stores
  has_many :rag_chunks, through: :rag_documents
  has_many :rag_queries, dependent: :destroy

  # Subscription tracking
  has_many :subscription_events, dependent: :destroy

  # RAG and Knowledge Base
  has_many :knowledge_documents, dependent: :destroy
  has_many :conversation_embeddings, dependent: :destroy
  has_many :integration_embeddings, dependent: :destroy

  # Custom Agent Definitions
  has_many :custom_agent_definitions, dependent: :destroy

  # Agent Lightning - RL-based optimization
  has_many :agent_lightning_traces, dependent: :destroy
  has_many :agent_llm_calls, dependent: :destroy
  has_many :agent_tool_executions, dependent: :destroy
  has_many :agent_phase_executions, dependent: :destroy
  has_many :agent_rewards, dependent: :destroy
  has_many :agent_training_jobs, dependent: :destroy
  has_one :agent_lightning_config, dependent: :destroy

  # Agent Plugins and Scheduled Tasks
  has_many :agent_plugins, dependent: :destroy
  has_many :scheduled_agent_tasks, dependent: :destroy
  has_many :agent_work_items, dependent: :destroy
  
  # Extensible Module System
  has_many :apps, dependent: :destroy
  has_many :app_modules, dependent: :destroy
  has_many :module_canvases, class_name: "ModuleCanvas", dependent: :destroy
  has_many :module_codes, dependent: :destroy
  has_many :module_actions, dependent: :destroy
  has_many :module_webhooks, dependent: :destroy
  has_many :custom_field_definitions, dependent: :destroy

  # Living Platform - Autonomous Evolution
  has_many :platform_perceptions, dependent: :destroy
  has_many :agent_goals, dependent: :destroy
  has_many :platform_anomalies, dependent: :destroy
  has_many :evolution_cycles, dependent: :destroy
  has_many :agent_reflections, dependent: :destroy

  # Platform Evolution Engine - Self-Healing
  has_many :support_tickets, dependent: :destroy
  has_many :debug_sessions, dependent: :destroy
  has_many :code_fixes, dependent: :destroy
  has_many :error_log_entries, dependent: :destroy

  # Context Graph - Decision Tracing
  has_many :decision_traces, dependent: :destroy
  
  # Subscription status accessor
  def subscription_status
    read_attribute(:subscription_status) || 'inactive'
  end

  # JSONB settings accessor
  store_accessor :settings, :timezone, :currency, :date_format, :logo_url, :primary_color,
                 :slack_notifications_enabled, :slack_webhook_url, :email_notifications_enabled,
                 :default_ai_model, :canvas_theme
  
  # Notification settings helpers
  def slack_notifications_enabled?
    slack_notifications_enabled == true || slack_notifications_enabled == 'true'
  end
  
  def email_notifications_enabled?
    # Default to true for email
    email_notifications_enabled != false && email_notifications_enabled != 'false'
  end

  # Custom methods
  def owner
    entity_users.find_by(role: "owner")&.user
  end

  def admins
    users.includes(:entity_users).where(entity_users: { role: [ "owner", "admin" ] })
  end

  def members
    users.includes(:entity_users).where(entity_users: { role: "member" })
  end

  # Slug generation
  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  # Subscription history helpers
  def subscription_history
    subscription_events.recent.map do |event|
      {
        date: event.created_at.strftime('%Y-%m-%d %H:%M:%S'),
        event_type: event.event_type,
        status_change: "#{event.previous_status || 'nil'} → #{event.new_status}",
        plan_change: "#{event.previous_plan || 'nil'} → #{event.new_plan || 'nil'}",
        triggered_by: event.triggered_by,
        metadata: event.metadata
      }
    end
  end

  def print_subscription_history
    puts "\n" + "=" * 80
    puts "Subscription History for: #{name}"
    puts "=" * 80

    if subscription_events.empty?
      puts "No subscription events recorded yet."
      return
    end

    subscription_events.recent.each do |event|
      puts "\n#{event.created_at.strftime('%Y-%m-%d %H:%M:%S')}"
      puts "  Event: #{event.event_type}"
      puts "  Status: #{event.previous_status || 'none'} → #{event.new_status}"
      puts "  Plan: #{event.previous_plan || 'none'} → #{event.new_plan || 'none'}" if event.previous_plan || event.new_plan
      puts "  Triggered by: #{event.triggered_by}"
      puts "  Metadata: #{event.metadata.inspect}" if event.metadata.present?
    end

    puts "\n" + "=" * 80
    puts "Total Events: #{subscription_events.count}"
    puts "=" * 80
  end

  def subscription_stats
    {
      total_events: subscription_events.count,
      subscriptions_created: subscription_events.where(event_type: 'subscription_created').count,
      subscriptions_cancelled: subscription_events.where(event_type: 'subscription_cancelled').count,
      plan_changes: subscription_events.where(event_type: 'plan_changed').count,
      payment_failures: subscription_events.where(event_type: 'payment_failed').count,
      payment_successes: subscription_events.where(event_type: 'payment_succeeded').count,
      first_subscription: subscription_events.where(event_type: 'subscription_created').order(:created_at).first&.created_at,
      last_event: subscription_events.order(:created_at).last&.created_at
    }
  end

  private

  def generate_slug
    base_slug = name.parameterize
    self.slug = base_slug

    # Check for uniqueness
    counter = 1
    while Entity.where(slug: slug).exists?
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def create_default_policies
    DefaultPoliciesService.create_for(self)
  rescue => e
    Rails.logger.warn "[Entity] Failed to create default policies: #{e.message}"
    # Don't fail entity creation if policies fail
  end
end
