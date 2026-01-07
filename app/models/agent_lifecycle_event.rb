# frozen_string_literal: true

# AgentLifecycleEvent - Tracks significant events in an agent's life
#
# Records the full lifecycle of agents from birth to retirement:
# - birth: Agent created (by user, desire engine, or evolution)
# - training_started: Agent entered training/school
# - training_completed: Agent completed training
# - maturation: Agent graduated from training to full operation
# - promotion: Agent upgraded (better model, new capabilities)
# - demotion: Agent downgraded (removed capabilities, simpler model)
# - retirement: Agent deprecated and archived
# - resurrection: Retired agent brought back
#
# Integrates with:
# - AgentSchoolEnrollment for training events
# - AgentGoal for goal-triggered events
# - EvolutionService for performance snapshots
#
class AgentLifecycleEvent < ApplicationRecord
  belongs_to :entity
  belongs_to :agent_plugin
  belongs_to :triggered_by_goal, class_name: 'AgentGoal', optional: true
  belongs_to :school_enrollment, class_name: 'AgentSchoolEnrollment', optional: true

  EVENT_TYPES = %w[
    birth 
    training_started 
    training_completed 
    maturation 
    promotion 
    demotion 
    capability_added 
    capability_removed
    specialization_discovered
    retirement 
    resurrection
  ].freeze

  TRIGGERS = %w[
    desire_engine 
    user_request 
    evolution_cycle 
    system_detection 
    agent_school
    anomaly_response
    performance_threshold
  ].freeze

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :triggered_by, inclusion: { in: TRIGGERS }, allow_nil: true

  scope :for_agent, ->(agent) { where(agent_plugin: agent) }
  scope :by_type, ->(type) { where(event_type: type) }
  scope :births, -> { by_type('birth') }
  scope :retirements, -> { by_type('retirement') }
  scope :training_events, -> { where(event_type: %w[training_started training_completed maturation]) }
  scope :recent, -> { order(created_at: :desc) }
  scope :in_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  # ═══════════════════════════════════════════════════════════════════════════
  # EVENT HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def birth?
    event_type == 'birth'
  end

  def retirement?
    event_type == 'retirement'
  end

  def training_event?
    %w[training_started training_completed maturation].include?(event_type)
  end

  def positive_event?
    %w[birth maturation promotion capability_added specialization_discovered resurrection].include?(event_type)
  end

  def negative_event?
    %w[demotion capability_removed retirement].include?(event_type)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # RELATED AGENTS
  # ═══════════════════════════════════════════════════════════════════════════

  def parent_agents
    return [] unless related_agents.is_a?(Array)
    
    parent_ids = related_agents.select { |r| r['role'] == 'parent' }.map { |r| r['id'] }
    AgentPlugin.where(id: parent_ids)
  end

  def successor_agent
    return nil unless related_agents.is_a?(Array)
    
    successor = related_agents.find { |r| r['role'] == 'successor' }
    AgentPlugin.find_by(id: successor['id']) if successor
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SUMMARY
  # ═══════════════════════════════════════════════════════════════════════════

  def summary
    {
      event_type: event_type,
      agent_name: agent_plugin.name,
      description: description,
      triggered_by: triggered_by,
      timestamp: created_at,
      has_metrics: metrics_snapshot.present?
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CLASS METHODS - Event Creation Helpers
  # ═══════════════════════════════════════════════════════════════════════════

  class << self
    def record_birth(agent, trigger:, goal: nil, parent_agents: [], reason: nil)
      create!(
        entity: agent.entity,
        agent_plugin: agent,
        event_type: 'birth',
        description: reason || "Agent #{agent.name} was created",
        triggered_by: trigger,
        triggered_by_goal: goal,
        related_agents: parent_agents.map { |p| { id: p.id, slug: p.slug, role: 'parent' } },
        metrics_snapshot: {},
        event_data: { 
          initial_config: agent.configuration,
          initial_tools: agent.agent_tools.pluck(:tool_name)
        }
      )
    end

    def record_training_start(agent, enrollment:, trigger: 'agent_school')
      evolution_service = Agents::EvolutionService.new(entity: agent.entity)
      metrics = evolution_service.analyze_agent(agent) rescue {}
      
      create!(
        entity: agent.entity,
        agent_plugin: agent,
        event_type: 'training_started',
        description: "Agent #{agent.name} entered training",
        triggered_by: trigger,
        school_enrollment: enrollment,
        metrics_snapshot: metrics[:performance] || {},
        event_data: { enrollment_reason: enrollment.enrollment_reason }
      )
    end

    def record_maturation(agent, enrollment: nil, trigger: 'agent_school')
      evolution_service = Agents::EvolutionService.new(entity: agent.entity)
      metrics = evolution_service.analyze_agent(agent) rescue {}
      
      create!(
        entity: agent.entity,
        agent_plugin: agent,
        event_type: 'maturation',
        description: "Agent #{agent.name} graduated from training",
        triggered_by: trigger,
        school_enrollment: enrollment,
        metrics_snapshot: metrics[:performance] || {},
        event_data: { 
          training_duration: enrollment&.duration,
          final_curriculum: enrollment&.curriculum_applied
        }
      )
    end

    def record_retirement(agent, trigger:, goal: nil, successor: nil, reason: nil)
      evolution_service = Agents::EvolutionService.new(entity: agent.entity)
      metrics = evolution_service.analyze_agent(agent) rescue {}
      
      related = []
      related << { id: successor.id, slug: successor.slug, role: 'successor' } if successor
      
      create!(
        entity: agent.entity,
        agent_plugin: agent,
        event_type: 'retirement',
        description: reason || "Agent #{agent.name} was retired",
        triggered_by: trigger,
        triggered_by_goal: goal,
        related_agents: related,
        metrics_snapshot: metrics[:performance] || {},
        event_data: {
          final_config: agent.configuration,
          lifetime_executions: agent.agent_plugin_executions.count,
          lifetime_success_rate: agent.lifetime_success_rate
        }
      )
    end

    def record_capability_change(agent, capability:, added:, trigger:, goal: nil)
      create!(
        entity: agent.entity,
        agent_plugin: agent,
        event_type: added ? 'capability_added' : 'capability_removed',
        description: "#{added ? 'Added' : 'Removed'} capability: #{capability}",
        triggered_by: trigger,
        triggered_by_goal: goal,
        event_data: { capability: capability }
      )
    end

    def record_specialization(agent, specialization:, trigger: 'evolution_cycle')
      create!(
        entity: agent.entity,
        agent_plugin: agent,
        event_type: 'specialization_discovered',
        description: "Discovered specialization: #{specialization}",
        triggered_by: trigger,
        event_data: { specialization: specialization }
      )
    end

    # Statistics for an entity
    def lifecycle_stats(entity, days: 30)
      events = where(entity: entity).where('created_at > ?', days.days.ago)
      
      {
        total_events: events.count,
        births: events.births.count,
        retirements: events.retirements.count,
        training_completions: events.by_type('training_completed').count,
        maturations: events.by_type('maturation').count,
        net_agent_change: events.births.count - events.retirements.count
      }
    end
  end
end


