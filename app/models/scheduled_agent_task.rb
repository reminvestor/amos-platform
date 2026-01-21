# frozen_string_literal: true

# == Schema Information
#
# Table name: scheduled_agent_tasks
#
#  id                    :bigint           not null, primary key
#  entity_id             :bigint           not null
#  user_id               :bigint           not null
#  agent_plugin_id       :bigint
#  name                  :string           not null
#  description           :text
#  task_type             :string           not null
#  prompt                :text             not null
#  schedule_type         :string           not null
#  cron_expression       :string
#  run_at_time           :time
#  run_on_day            :integer
#  timezone              :string           default("UTC")
#  next_run_at           :datetime
#  last_run_at           :datetime
#  run_count             :integer          default(0)
#  failure_count         :integer          default(0)
#  consecutive_failures  :integer          default(0)
#  input_context         :jsonb            default({})
#  output_config         :jsonb            default({})
#  metadata              :jsonb            default({})
#  status                :string           default("active")
#  enabled               :boolean          default(TRUE)
#  max_runs              :integer
#  expires_at            :datetime
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Execution Mode (stored in input_context):
#  execution_mode        :string           # 'scout' (default), 'agent_only', 'tool_only'
#  required_tools        :array            # Tools that MUST be used (for tool_only mode)
#  required_agent_slug   :string           # Agent that MUST be used (for agent_only mode)
#  allow_fallback        :boolean          # If required tool/agent fails, allow Scout to try
#
class ScheduledAgentTask < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  belongs_to :agent_plugin, optional: true
  belongs_to :app_module, optional: true  # If part of an extensible module
  
  has_many :scheduled_task_runs, dependent: :destroy
  has_many :agent_work_items, through: :scheduled_task_runs
  
  # Validations
  validates :name, presence: true
  validates :task_type, presence: true, inclusion: { 
    in: %w[email_summary report_generation data_sync custom email_management research_update]
  }
  validates :prompt, presence: true
  validates :schedule_type, presence: true, inclusion: { 
    in: %w[once daily weekly monthly cron]
  }
  validates :status, presence: true, inclusion: { 
    in: %w[active paused completed failed archived]
  }
  validates :cron_expression, presence: true, if: -> { schedule_type == 'cron' }
  validates :run_at_time, presence: true, if: -> { schedule_type.in?(%w[daily weekly monthly]) }
  validates :run_on_day, presence: true, if: -> { schedule_type.in?(%w[weekly monthly]) }
  
  # Scopes
  scope :active, -> { where(status: 'active', enabled: true) }
  scope :paused, -> { where(status: 'paused') }
  scope :due_now, -> { active.where('next_run_at <= ?', Time.current) }
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :for_user, ->(user) { where(user: user) }
  scope :by_type, ->(type) { where(task_type: type) }
  
  # Callbacks
  before_create :calculate_next_run
  before_update :recalculate_next_run, if: :schedule_changed?
  
  # Task type descriptions
  TASK_TYPES = {
    'email_summary' => {
      name: 'Email Summary',
      description: 'Summarize and organize incoming emails',
      icon: '📧'
    },
    'report_generation' => {
      name: 'Report Generation',
      description: 'Generate periodic reports and analytics',
      icon: '📊'
    },
    'data_sync' => {
      name: 'Data Sync',
      description: 'Synchronize data from external sources',
      icon: '🔄'
    },
    'email_management' => {
      name: 'Email Management',
      description: 'Draft responses and manage email workflow',
      icon: '✉️'
    },
    'research_update' => {
      name: 'Research Update',
      description: 'Gather and summarize industry news and updates',
      icon: '🔍'
    },
    'custom' => {
      name: 'Custom Task',
      description: 'Custom scheduled agent task',
      icon: '⚙️'
    }
  }.freeze
  
  # Instance methods
  def due?
    enabled? && status == 'active' && next_run_at.present? && next_run_at <= Time.current
  end
  
  def can_run?
    return false unless enabled? && status == 'active'
    return false if expired?
    return false if max_runs.present? && run_count >= max_runs
    return false if consecutive_failures >= 3  # Auto-pause after 3 consecutive failures
    
    # Check if user has sufficient token balance
    # Scheduled tasks should NOT run if user is out of tokens
    # This prevents runaway charges when balance goes negative
    unless has_sufficient_tokens?
      Rails.logger.warn "🚫 [ScheduledTask] Blocking task #{id} (#{name}) - user #{user_id} has insufficient token balance"
      return false
    end
    
    true
  end
  
  # Check if user/entity has sufficient tokens to run this task
  # Uses a minimum threshold to prevent running tasks when balance is too low
  def has_sufficient_tokens?
    # Estimate ~1000 tokens per task execution (conservative)
    # This allows tasks to run when balance is positive but blocks when negative
    estimated_tokens_needed = 1000
    
    if entity&.use_shared_token_pool
      billing_account = EntityBillingAccount.find_by(entity: entity)
      return true unless billing_account  # If no account, allow (will create on first charge)
      
      # Block if balance is negative OR below threshold
      # Allow a small grace period (up to -10000 tokens) to finish in-flight work
      billing_account.work_token_balance > -10000
    else
      billing_account = UserBillingAccount.find_by(user: user)
      return true unless billing_account  # If no account, allow (will create on first charge)
      
      # Block if balance is negative OR below threshold
      billing_account.work_token_balance > -10000
    end
  end
  
  def expired?
    expires_at.present? && expires_at < Time.current
  end
  
  def pause!
    update!(status: 'paused')
  end
  
  def resume!
    update!(status: 'active')
    calculate_next_run!
  end
  
  def archive!
    update!(status: 'archived', enabled: false)
  end
  
  def record_run!(success:, run: nil)
    if success
      update!(
        last_run_at: Time.current,
        run_count: run_count + 1,
        consecutive_failures: 0
      )
    else
      new_consecutive = consecutive_failures + 1
      update!(
        last_run_at: Time.current,
        run_count: run_count + 1,
        failure_count: failure_count + 1,
        consecutive_failures: new_consecutive
      )
      
      # Auto-pause after 3 consecutive failures
      pause! if new_consecutive >= 3
    end
    
    # Check if we've hit max runs
    if max_runs.present? && run_count >= max_runs
      update!(status: 'completed')
    else
      calculate_next_run!
    end
  end
  
  def calculate_next_run!
    calculate_next_run
    save!
  end
  
  def task_type_info
    TASK_TYPES[task_type] || TASK_TYPES['custom']
  end
  
  def output_method
    output_config['method'] || 'notification'  # notification, email, both
  end
  
  def output_email
    output_config['email'] || user.email
  end
  
  # Execution mode helpers
  def execution_mode
    input_context['execution_mode'] || 'scout'  # scout, agent_only, tool_only
  end
  
  def deterministic?
    execution_mode.in?(%w[agent_only tool_only])
  end
  
  def required_tools
    input_context['required_tools'] || []
  end
  
  def required_agent_slug
    input_context['required_agent_slug']
  end
  
  def allow_fallback?
    input_context['allow_fallback'] != false  # Default to true
  end
  
  def required_agent
    return nil unless required_agent_slug.present?
    AgentPlugin.find_by(slug: required_agent_slug, entity: entity) ||
      AgentPlugin.find_by(slug: required_agent_slug, entity: nil)  # System agents
  end
  
  private
  
  def calculate_next_run
    self.next_run_at = case schedule_type
    when 'once'
      # For one-time tasks, use the specified time or now
      input_context['run_at'] ? Time.zone.parse(input_context['run_at']) : Time.current
    when 'daily'
      next_daily_run
    when 'weekly'
      next_weekly_run
    when 'monthly'
      next_monthly_run
    when 'cron'
      next_cron_run
    end
  end
  
  def recalculate_next_run
    calculate_next_run
  end
  
  def schedule_changed?
    schedule_type_changed? || cron_expression_changed? || 
    run_at_time_changed? || run_on_day_changed? || timezone_changed?
  end
  
  def next_daily_run
    return nil unless run_at_time
    
    tz = ActiveSupport::TimeZone[timezone] || Time.zone
    today_run = tz.now.change(hour: run_at_time.hour, min: run_at_time.min, sec: 0)
    
    if today_run > tz.now
      today_run
    else
      today_run + 1.day
    end
  end
  
  def next_weekly_run
    return nil unless run_at_time && run_on_day
    
    tz = ActiveSupport::TimeZone[timezone] || Time.zone
    now = tz.now
    
    # Find next occurrence of the specified day
    days_until = (run_on_day - now.wday) % 7
    days_until = 7 if days_until == 0 && now.hour * 60 + now.min >= run_at_time.hour * 60 + run_at_time.min
    
    next_run = now.beginning_of_day + days_until.days
    next_run.change(hour: run_at_time.hour, min: run_at_time.min, sec: 0)
  end
  
  def next_monthly_run
    return nil unless run_at_time && run_on_day
    
    tz = ActiveSupport::TimeZone[timezone] || Time.zone
    now = tz.now
    
    # Find next occurrence of the specified day of month
    this_month_run = now.beginning_of_month + (run_on_day - 1).days
    this_month_run = this_month_run.change(hour: run_at_time.hour, min: run_at_time.min, sec: 0)
    
    if this_month_run > now
      this_month_run
    else
      next_month = now.next_month.beginning_of_month + (run_on_day - 1).days
      next_month.change(hour: run_at_time.hour, min: run_at_time.min, sec: 0)
    end
  end
  
  def next_cron_run
    return nil unless cron_expression.present?
    
    begin
      cron = Fugit::Cron.parse(cron_expression)
      tz = ActiveSupport::TimeZone[timezone] || Time.zone
      cron.next_time(tz.now).to_t
    rescue => e
      Rails.logger.error "Failed to parse cron expression '#{cron_expression}': #{e.message}"
      nil
    end
  end
end

