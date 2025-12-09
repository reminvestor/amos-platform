# == Schema Information
#
# Table name: agent_plugins
#
#  id                       :bigint           not null, primary key
#  name                     :string           not null
#  slug                     :string           not null
#  role                     :string           not null
#  description              :text
#  version                  :string           default("1.0.0")
#  status                   :string           default("draft"), not null
#  agent_class              :string           default("Agents::Specialized::ExecutorAgent")
#  configuration            :jsonb            default({})
#  system_prompt            :jsonb            default({})
#  capabilities_definition  :jsonb            default({})
#  priority                 :integer          default(50)
#  entity_id                :bigint
#  user_id                  :bigint
#  last_activated_at        :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
class AgentPlugin < ApplicationRecord
  # Concerns
  include Reviewable

  # Associations
  belongs_to :entity, optional: true  # nil = system-wide agent
  belongs_to :user, optional: true    # nil = system agent, otherwise tracks creator
  belongs_to :parent_agent, class_name: 'AgentPlugin', optional: true
  belongs_to :school_enrollment, class_name: 'AgentSchoolEnrollment', optional: true

  has_many :agent_capabilities, dependent: :destroy
  has_many :agent_tools, dependent: :destroy
  has_many :agent_template_bindings, dependent: :destroy
  has_many :workflow_templates, through: :agent_template_bindings
  has_many :agent_plugin_executions, dependent: :destroy
  has_many :agent_input_requests, through: :agent_plugin_executions
  has_many :user_feedbacks, through: :agent_plugin_executions, source: :feedbacks

  # Collaboration system associations
  has_one :energy_state, class_name: 'AgentEnergyState', dependent: :destroy
  has_one :decision_boundary, class_name: 'AgentDecisionBoundary', dependent: :destroy
  has_many :capability_beliefs, class_name: 'AgentCapabilityBelief', dependent: :destroy
  has_many :relationships_as_requester, class_name: 'AgentRelationship', foreign_key: :requester_id, dependent: :destroy
  has_many :relationships_as_helper, class_name: 'AgentRelationship', foreign_key: :helper_id, dependent: :destroy
  has_many :collaboration_requests_made, class_name: 'AgentCollaborationRequest', foreign_key: :requesting_agent_id
  has_many :collaboration_requests_received, class_name: 'AgentCollaborationRequest', foreign_key: :helper_agent_id
  has_many :school_enrollments, class_name: 'AgentSchoolEnrollment', dependent: :destroy
  has_many :child_agents, class_name: 'AgentPlugin', foreign_key: :parent_agent_id

  # CRM associations
  has_many :assigned_opportunities, class_name: 'Opportunity', foreign_key: :assigned_agent_id, dependent: :nullify
  has_many :assigned_contacts, class_name: 'Contact', foreign_key: :assigned_agent_id, dependent: :nullify
  has_many :assigned_activities, class_name: 'Activity', foreign_key: :assigned_agent_id, dependent: :nullify
  has_many :performed_activities, class_name: 'Activity', foreign_key: :performed_by_agent_id, dependent: :nullify

  # Nested attributes
  accepts_nested_attributes_for :agent_capabilities, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :agent_tools, allow_destroy: true, reject_if: :all_blank

  # Validations
  validates :name, presence: true, length: { minimum: 3, maximum: 100 }
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/, message: "only lowercase letters, numbers, and underscores" }
  validates :role, inclusion: { in: %w[executor planner analyst verifier fixer architect engineer custom] }, allow_nil: true
  validates :status, presence: true, inclusion: { in: %w[draft active deprecated in_school probation archived sabbatical testing] }
  validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :version, format: { with: /\A\d+\.\d+\.\d+\z/, message: "must be in format X.Y.Z" }, allow_blank: true
  validates :execution_strategy, inclusion: { in: %w[standard workflow remote_http], message: "%{value} is not a valid strategy" }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :available, -> { where(status: %w[active probation]) }  # Can receive tasks
  scope :for_entity, ->(entity) { where(entity: entity).or(where(entity: nil)) }
  scope :by_role, ->(role) { where(role: role) }
  scope :by_priority, -> { order(priority: :desc) }
  scope :system_wide, -> { where(entity_id: nil) }
  scope :entity_specific, -> { where.not(entity_id: nil) }
  scope :created_by, ->(user) { where(user: user) }
  scope :editable_by, ->(user) { user.admin? ? all : where(user: user) }
  scope :in_school, -> { where(status: 'in_school') }
  scope :on_probation, -> { where(status: 'probation') }
  scope :with_protected_status, -> { where(protected_status: true) }

  # Callbacks
  before_validation :generate_slug, if: -> { slug.blank? && name.present? }
  before_save :normalize_configuration
  before_save :parse_json_fields
  
  # Vector search configuration
  has_neighbors :embedding
  
  # Update embedding when relevant fields change
  after_save :update_embedding, if: -> { saved_change_to_name? || saved_change_to_description? || saved_change_to_role? || saved_change_to_capabilities_definition? || saved_change_to_status? }

  # Class methods
  def self.search_by_similarity(query, limit: 5, entity: nil)
    # Generate embedding for the query
    query_embedding = AiAgents::VectorStore.instance.generate_embedding(query)

    # Use pgvector nearest_neighbors search
    # Filter by entity scope: entity-specific agents + system-wide (entity_id: nil)
    base_scope = active
    base_scope = base_scope.for_entity(entity) if entity.present?
    
    base_scope.nearest_neighbors(:embedding, query_embedding, distance: "cosine").first(limit)
  rescue => e
    Rails.logger.error "Vector search failed: #{e.message}"
    # Fallback to keyword search if vector search fails
    fallback_scope = active
    fallback_scope = fallback_scope.for_entity(entity) if entity.present?
    fallback_scope.where("description ILIKE ? OR name ILIKE ?", "%#{query}%", "%#{query}%").limit(limit)
  end

  def self.discover_by_capabilities(capability_names, entity: nil)
    # Find agents that have ALL the required capabilities
    joins(:agent_capabilities)
      .where(agent_capabilities: { capability_name: capability_names })
      .for_entity(entity)
      .active
      .group('agent_plugins.id')
      .having('COUNT(DISTINCT agent_capabilities.capability_name) = ?', capability_names.size)
      .by_priority
  end

  def self.find_for_phase(phase, template: nil, entity: nil)
    # Find agents suitable for a specific workflow phase
    if template
      # First try to find agents explicitly bound to this template+phase
      bound_agents = joins(:agent_template_bindings)
                      .where(agent_template_bindings: { workflow_template: template, phase: phase })
                      .for_entity(entity)
                      .active
                      .by_priority

      return bound_agents if bound_agents.exists?
    end

    # Fallback to agents suitable for the phase based on role
    role_map = {
      'gather_context' => %w[executor analyst],
      'execute_goal' => %w[executor],
      'validate_result' => %w[verifier executor]
    }

    where(role: role_map[phase] || []).for_entity(entity).active.by_priority
  end

  # Instance methods
  def activate!
    update!(status: 'active', last_activated_at: Time.current)
  end

  def deactivate!
    update!(status: 'deprecated')
  end

  def system_wide?
    entity_id.nil?
  end

  def system_agent?
    user_id.nil?
  end

  def editable_by?(user)
    return true if user.admin?
    return false if user_id.nil? # System agents can't be edited by non-admins
    user_id == user.id
  end

  def owned_by?(user)
    user_id == user.id
  end

  # ============================================
  # REPUTATION & USER SATISFACTION
  # ============================================

  # Calculate user satisfaction based on feedback
  # Returns a score from 0.0 to 1.0
  def user_satisfaction_score
    feedbacks = UserFeedback.for_agent(id)
    total = feedbacks.count
    return 0.5 if total < 5 # Not enough data for reliable score

    positive = feedbacks.positive.count
    negative = feedbacks.negative.count
    rated = positive + negative

    return 0.5 if rated.zero?

    (positive.to_f / rated).clamp(0.0, 1.0)
  end

  # Combined reputation score considering:
  # - Technical success rate (energy economy)
  # - User satisfaction (feedback)
  # - ELO rating (competitive ranking)
  def combined_reputation_score
    energy_score = energy_state&.success_rate || 0.5
    user_score = user_satisfaction_score
    elo_normalized = ((energy_state&.elo_rating || 1000) - 800) / 400.0

    # Weights: 40% technical, 40% user satisfaction, 20% ELO
    (
      energy_score * 0.4 +
      user_score * 0.4 +
      elo_normalized.clamp(0.0, 1.0) * 0.2
    ).clamp(0.0, 1.0)
  end

  # Get feedback stats for this agent
  def feedback_stats
    feedbacks = UserFeedback.for_agent(id)
    {
      total: feedbacks.count,
      positive: feedbacks.positive.count,
      negative: feedbacks.negative.count,
      neutral: feedbacks.neutral.count,
      satisfaction_score: user_satisfaction_score,
      recent_comments: feedbacks.with_comments.recent.limit(5).pluck(:comment, :rating)
    }
  end

  # ============================================
  # COLLABORATION SYSTEM
  # ============================================

  def ensure_energy_state!
    energy_state || create_energy_state!(entity: entity || Entity.first)
  end

  def ensure_decision_boundary!
    decision_boundary || create_decision_boundary!
  end

  def current_energy
    energy_state&.current_energy || 50.0
  end

  def in_school?
    status == 'in_school'
  end

  def on_probation?
    status == 'probation'
  end

  def on_sabbatical?
    status == 'sabbatical' && sabbatical_until.present? && sabbatical_until > Time.current
  end

  def available_for_tasks?
    %w[active probation].include?(status) && !on_sabbatical?
  end

  def can_help_others?
    available_for_tasks? && current_energy >= 30
  end

  def should_ask_for_help?(task_confidence)
    ensure_decision_boundary!.should_ask_for_help?(task_confidence)
  end

  def estimate_confidence(task)
    # Estimate confidence based on capability beliefs
    task_type = classify_task_type(task)
    belief = capability_beliefs.find_by(task_type: task_type)

    if belief
      belief.confidence_for_task
    else
      50.0  # Default confidence for unknown task types
    end
  end

  def capability_for_task(task)
    task_type = classify_task_type(task)
    belief = capability_beliefs.find_by(task_type: task_type)
    belief&.avg_quality || 0.5
  end

  def success_rate_for_task_type(task)
    task_type = classify_task_type(task)
    belief = capability_beliefs.find_by(task_type: task_type)
    belief&.success_rate || 0.5
  end

  def update_capability_belief!(task_type:, success:, quality:)
    belief = capability_beliefs.find_or_create_by!(task_type: task_type)
    belief.update_from_outcome!(success: success, quality: quality)
  end

  def lifetime_success_rate
    energy_state&.success_rate || 0.5
  end

  def total_tasks
    (energy_state&.tasks_completed || 0) + (energy_state&.tasks_failed || 0)
  end

  def active_task_count
    agent_plugin_executions.where(status: 'running').count
  end

  def availability_score
    # 1.0 = fully available, 0.0 = overloaded
    active = active_task_count
    max_concurrent = 3

    if active >= max_concurrent
      0.0
    else
      1.0 - (active.to_f / max_concurrent)
    end
  end

  private

  def classify_task_type(task)
    # Simple task type classification based on keywords
    task_description = task.is_a?(String) ? task : task[:description] || task['description'] || ''
    task_description = task_description.to_s.downcase

    if task_description.include?('analyze') || task_description.include?('analysis')
      'analysis'
    elsif task_description.include?('create') || task_description.include?('generate')
      'creation'
    elsif task_description.include?('research') || task_description.include?('find')
      'research'
    elsif task_description.include?('integrate') || task_description.include?('api')
      'integration'
    elsif task_description.include?('email') || task_description.include?('message')
      'communication'
    elsif task_description.include?('report') || task_description.include?('visualiz')
      'reporting'
    else
      'general'
    end
  end

  public

  def has_capability?(capability_name)
    agent_capabilities.exists?(capability_name: capability_name)
  end

  def required_tools
    agent_tools.where(required: true).pluck(:tool_name)
  end

  def capability_names
    agent_capabilities.pluck(:capability_name)
  end

  # Configuration helpers
  def canvas_on_completion
    configuration['canvas_on_completion']
  end

  def include_business_data?
    configuration['include_business_data'] == true || configuration['include_business_data'] == 'true'
  end

  def instantiate(context = {})
    # Use standard executor if no custom class specified
    if agent_class.blank?
      return Agents::StandardPluginExecutor.new(
        role: role.to_sym,
        capabilities: capability_names,
        system_prompt: system_prompt,
        config: configuration.merge(context.fetch(:config, {})),
        context: context.merge(agent_plugin: self)
      )
    end

    # Dynamically load the custom agent class
    klass = agent_class.constantize

    # Build agent with configuration
    klass.new(
      role: role.to_sym,
      capabilities: capability_names,
      system_prompt: system_prompt,
      config: configuration.merge(context.fetch(:config, {})),
      context: context
    )
  rescue NameError => e
    Rails.logger.error "Failed to instantiate agent #{name}: #{e.message}"
    raise ArgumentError, "Invalid agent class: #{agent_class}"
  end

  def validate_capability_contracts
    agent_capabilities.all? do |cap|
      next true if cap.contract_schema.blank?

      begin
        # Basic JSON schema validation
        cap.contract_schema.is_a?(Hash) &&
          cap.contract_schema.key?('inputs') &&
          cap.contract_schema.key?('outputs')
      rescue => e
        errors.add(:base, "Invalid contract schema for #{cap.capability_name}: #{e.message}")
        false
      end
    end
  end

  def execution_stats(since: 30.days.ago)
    execs = agent_plugin_executions.where('created_at >= ?', since)

    # Calculate total cost from executions with model tracking
    total_cost = execs.select { |e| e.model_id.present? }.sum(&:calculate_cost)

    {
      total_executions: execs.count,
      successful: execs.where(status: 'completed').count,
      failed: execs.where(status: 'failed').count,
      avg_duration_ms: execs.where(status: 'completed').average(:duration_ms)&.to_i || 0,
      total_tokens: execs.sum(:tokens_used),
      total_cost: total_cost.round(4),
      success_rate: calculate_success_rate(execs)
    }
  end

  private

  def generate_slug
    self.slug = name.parameterize.underscore
  end

  def normalize_configuration
    # Set empty agent_class to nil for cleaner data
    self.agent_class = nil if agent_class.blank?

    # Ensure JSONB fields are hashes
    self.configuration ||= {}
    self.system_prompt ||= {}
    self.capabilities_definition ||= {}
  end

  def parse_json_fields
    # Parse JSON strings into hashes for JSONB columns
    # This handles form submissions where JSON is sent as a string

    # Configuration
    if configuration.is_a?(String) && configuration.present?
      begin
        self.configuration = JSON.parse(configuration)
      rescue JSON::ParserError => e
        Rails.logger.warn "Failed to parse configuration JSON: #{e.message}"
        self.configuration = {}
      end
    end

    # System Prompt - can be string or hash
    if system_prompt.is_a?(String) && system_prompt.present?
      begin
        parsed = JSON.parse(system_prompt)
        # If it parses to a hash, use it; otherwise keep as string
        self.system_prompt = parsed.is_a?(Hash) ? parsed : { 'prompt' => system_prompt }
      rescue JSON::ParserError
        # Not JSON, treat as plain string and wrap in hash
        self.system_prompt = { 'prompt' => system_prompt }
      end
    end

    # Capabilities Definition
    if capabilities_definition.is_a?(String) && capabilities_definition.present?
      begin
        self.capabilities_definition = JSON.parse(capabilities_definition)
      rescue JSON::ParserError => e
        Rails.logger.warn "Failed to parse capabilities_definition JSON: #{e.message}"
        self.capabilities_definition = {}
      end
    end
  end

  def calculate_success_rate(executions)
    total = executions.count
    return 0 if total.zero?

    successful = executions.where(status: 'completed').count
    ((successful.to_f / total) * 100).round(2)
  end

  def update_embedding
    # Construct a rich text representation of the agent
    # This includes name, role, description, and capabilities
    
    caps = capability_names.join(", ")
    
    embedding_text = <<~TEXT
      Agent: #{name}
      Role: #{role}
      Description: #{description}
      Capabilities: #{caps}
      Tools: #{required_tools.join(", ")}
    TEXT
    
    # Generate embedding using VectorStore service
    vector = AiAgents::VectorStore.instance.generate_embedding(embedding_text)
    
    # Update the column directly to avoid triggering callbacks again
    update_column(:embedding, vector)
  rescue => e
    Rails.logger.error "Failed to update embedding for agent #{id}: #{e.message}"
  end
end
