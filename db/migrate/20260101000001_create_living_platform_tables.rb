# frozen_string_literal: true

# Living Platform Architecture - Core Tables
#
# This migration extends the existing agent infrastructure with:
# 1. Desire Engine - Autonomous goal generation
# 2. Evolution Loop - Extends existing EvolutionService with cycles
# 3. Metacognition Layer - Agent self-reflection
# 4. Society System - Extends existing AgentRelationship with knowledge sharing
# 5. Perception System - Global awareness and anomaly detection
# 6. Agent Lifecycle - Birth, maturation, retirement tracking
#
# EXISTING SYSTEMS WE BUILD ON (not duplicate):
# - AgentSchoolEnrollment (training/rehabilitation)
# - AgentRelationship (collaboration tracking)
# - Agents::EvolutionService (performance analysis)
# - AgentAbTest (A/B experiments)
# - AgentEnergyState/Transaction (energy system)
#
class CreateLivingPlatformTables < ActiveRecord::Migration[7.1]
  def change
    # ═══════════════════════════════════════════════════════════════════════════
    # SYSTEM 1: DESIRE ENGINE - Autonomous Goal Generation
    # Goals that the platform generates for itself, without human intervention
    # ═══════════════════════════════════════════════════════════════════════════
    
    create_table :agent_goals do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :agent_plugin, null: true, foreign_key: true  # null = entity-wide goal
      t.references :created_by_agent, null: true, foreign_key: { to_table: :agent_plugins }
      
      # Goal definition
      t.string :goal_type, null: false  # improvement, expansion, maintenance, learning, social
      t.string :title, null: false
      t.text :description
      t.integer :priority, default: 50  # 1-100, higher = more important
      t.string :status, default: 'pending'  # pending, scheduled, in_progress, completed, failed, cancelled
      
      # Target of the goal (polymorphic)
      t.string :target_type  # AgentPlugin, AppModule, ToolDefinition, Entity, etc.
      t.bigint :target_id
      
      # Metrics and criteria
      t.jsonb :success_criteria, default: {}  # What defines success
      t.jsonb :current_metrics, default: {}   # Current state before goal
      t.jsonb :target_metrics, default: {}    # Desired state after goal
      t.jsonb :suggested_actions, default: [] # Array of suggested action types
      
      # Execution - links to scheduled tasks or school enrollments
      t.datetime :scheduled_for
      t.datetime :started_at
      t.datetime :completed_at
      t.references :execution_task, null: true, foreign_key: { to_table: :scheduled_agent_tasks }
      t.references :school_enrollment, null: true, foreign_key: { to_table: :agent_school_enrollments }
      t.jsonb :execution_result, default: {}
      
      # Provenance
      t.string :source  # desire_engine, user_request, system_detection, agent_reflection, evolution_cycle
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    add_index :agent_goals, [:entity_id, :status]
    add_index :agent_goals, [:entity_id, :goal_type]
    add_index :agent_goals, [:agent_plugin_id, :status]
    add_index :agent_goals, [:target_type, :target_id]
    add_index :agent_goals, :scheduled_for
    
    # ═══════════════════════════════════════════════════════════════════════════
    # SYSTEM 2: EVOLUTION LOOP - Extends existing EvolutionService
    # Periodic evolution cycles with full lifecycle tracking
    # ═══════════════════════════════════════════════════════════════════════════
    
    create_table :evolution_cycles do |t|
      t.references :entity, null: false, foreign_key: true
      
      # Cycle info
      t.string :cycle_type, null: false  # daily, weekly, monthly, triggered
      t.string :status, default: 'running'  # running, completed, failed
      t.datetime :started_at
      t.datetime :completed_at
      
      # Perception phase results
      t.jsonb :metrics_snapshot, default: {}  # All metrics gathered
      t.jsonb :anomalies_detected, default: []
      t.jsonb :opportunities_detected, default: []
      t.jsonb :threats_detected, default: []
      
      # Analysis phase results (from EvolutionService)
      t.jsonb :analysis_results, default: {}
      t.jsonb :improvement_hypotheses, default: []
      
      # Experimentation phase - links to existing AgentAbTest
      t.integer :experiments_started, default: 0
      t.integer :experiments_completed, default: 0
      t.integer :experiments_successful, default: 0
      
      # Goals generated this cycle
      t.integer :goals_generated, default: 0
      t.integer :goals_completed, default: 0
      
      # Integration phase
      t.jsonb :evolutions_promoted, default: []  # Changes that were deployed
      t.jsonb :learnings, default: []  # What we learned this cycle
      
      t.timestamps
    end
    
    add_index :evolution_cycles, [:entity_id, :cycle_type]
    add_index :evolution_cycles, [:entity_id, :status]
    add_index :evolution_cycles, :started_at
    
    # Link existing AgentAbTest to evolution cycles
    add_reference :agent_ab_tests, :evolution_cycle, foreign_key: true, null: true
    add_reference :agent_ab_tests, :agent_goal, foreign_key: true, null: true
    
    # ═══════════════════════════════════════════════════════════════════════════
    # SYSTEM 3: METACOGNITION LAYER - Agent Self-Awareness
    # Agents reflect on their own performance after executions
    # ═══════════════════════════════════════════════════════════════════════════
    
    create_table :agent_reflections do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :agent_plugin, null: false, foreign_key: true
      t.references :agent_plugin_execution, null: true, foreign_key: true
      
      # Reflection type
      t.string :reflection_type, null: false  # execution, daily, weekly, triggered
      
      # Self-assessment scores (1-10)
      t.integer :efficiency_score
      t.integer :quality_score
      t.integer :tool_usage_score
      t.integer :communication_score
      t.integer :overall_score
      
      # Identified issues and learnings
      t.jsonb :identified_issues, default: []
      t.jsonb :improvement_ideas, default: []
      t.jsonb :knowledge_gaps, default: []
      t.jsonb :strengths_identified, default: []
      t.jsonb :skills_to_develop, default: []
      
      # Peer comparison (uses existing AgentRelationship data)
      t.jsonb :peer_comparison, default: {}
      
      # Learning plan - can trigger Agent School enrollment
      t.jsonb :learning_plan, default: {}
      t.boolean :learning_tasks_scheduled, default: false
      t.references :triggered_enrollment, null: true, foreign_key: { to_table: :agent_school_enrollments }
      
      # Raw reflection text from LLM
      t.text :raw_reflection
      
      t.timestamps
    end
    
    add_index :agent_reflections, [:agent_plugin_id, :reflection_type]
    add_index :agent_reflections, [:agent_plugin_id, :created_at]
    
    # ═══════════════════════════════════════════════════════════════════════════
    # SYSTEM 4: SOCIETY SYSTEM - Extends AgentRelationship
    # Knowledge sharing between agents (builds on existing trust/compatibility)
    # ═══════════════════════════════════════════════════════════════════════════
    
    create_table :agent_knowledge_shares do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :source_agent, null: false, foreign_key: { to_table: :agent_plugins }
      t.references :target_agent, null: false, foreign_key: { to_table: :agent_plugins }
      t.references :agent_relationship, null: true, foreign_key: true  # Links to existing relationship
      
      # Knowledge being shared
      t.string :knowledge_type  # discovery, technique, pattern, tool_usage, prompt_template
      t.string :title, null: false
      t.text :content
      t.jsonb :metadata, default: {}
      
      # Sharing context
      t.text :reason  # Why this knowledge was shared
      t.decimal :relevance_score, precision: 5, scale: 4
      
      # Outcome
      t.string :status, default: 'shared'  # shared, acknowledged, applied, rejected
      t.boolean :target_found_useful
      t.text :target_feedback
      
      t.timestamps
    end
    
    add_index :agent_knowledge_shares, [:source_agent_id, :target_agent_id]
    add_index :agent_knowledge_shares, [:target_agent_id, :status]
    
    # Extend AgentRelationship with knowledge sharing fields
    add_column :agent_relationships, :knowledge_shares_count, :integer, default: 0
    add_column :agent_relationships, :last_knowledge_share_at, :datetime
    add_column :agent_relationships, :relationship_type, :string  # peer, mentor_mentee, specialist_generalist
    
    # ═══════════════════════════════════════════════════════════════════════════
    # SYSTEM 5: PERCEPTION SYSTEM - Global Awareness
    # Platform-wide health monitoring and anomaly detection
    # ═══════════════════════════════════════════════════════════════════════════
    
    create_table :platform_perceptions do |t|
      t.references :entity, null: true, foreign_key: true  # null = global perception
      
      # Perception snapshot
      t.datetime :perceived_at, null: false
      t.string :perception_type, null: false  # routine, triggered, deep_scan
      
      # Health metrics
      t.decimal :overall_health_score, precision: 5, scale: 4
      t.jsonb :health_breakdown, default: {}  # Per-component health
      
      # Activity metrics
      t.integer :active_agents, default: 0
      t.integer :tasks_completed_24h, default: 0
      t.integer :tasks_failed_24h, default: 0
      t.decimal :success_rate_24h, precision: 5, scale: 4
      
      # Anomalies
      t.jsonb :anomalies, default: []
      t.integer :anomaly_count, default: 0
      t.integer :critical_anomalies, default: 0
      
      # Opportunities and threats
      t.jsonb :opportunities, default: []
      t.jsonb :threats, default: []
      
      # Actions taken
      t.jsonb :autonomous_actions_triggered, default: []
      t.integer :actions_count, default: 0
      
      t.timestamps
    end
    
    add_index :platform_perceptions, [:entity_id, :perceived_at]
    add_index :platform_perceptions, :perception_type
    add_index :platform_perceptions, :perceived_at
    
    create_table :platform_anomalies do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :platform_perception, null: true, foreign_key: true
      
      # Anomaly details
      t.string :anomaly_type, null: false  # performance_drop, error_spike, resource_anomaly, behavior_change
      t.string :severity, null: false  # low, medium, high, critical
      t.string :status, default: 'detected'  # detected, investigating, resolved, ignored
      
      # Target (polymorphic)
      t.string :target_type  # AgentPlugin, Entity, ToolDefinition, etc.
      t.bigint :target_id
      
      # Description
      t.string :title, null: false
      t.text :description
      t.jsonb :details, default: {}
      
      # Metrics that triggered detection
      t.jsonb :triggering_metrics, default: {}
      t.decimal :deviation_percent, precision: 8, scale: 4
      
      # Resolution - can trigger goals
      t.jsonb :suggested_actions, default: []
      t.jsonb :resolution_actions, default: []
      t.datetime :resolved_at
      t.text :resolution_notes
      t.references :triggered_goal, null: true, foreign_key: { to_table: :agent_goals }
      
      t.timestamps
    end
    
    add_index :platform_anomalies, [:entity_id, :status]
    add_index :platform_anomalies, [:entity_id, :severity]
    add_index :platform_anomalies, [:target_type, :target_id]
    
    # ═══════════════════════════════════════════════════════════════════════════
    # SYSTEM 6: AGENT LIFECYCLE - Birth, Maturation, Retirement
    # Tracks the full lifecycle of agents, integrates with Agent School
    # ═══════════════════════════════════════════════════════════════════════════
    
    create_table :agent_lifecycle_events do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :agent_plugin, null: false, foreign_key: true
      
      # Event type
      t.string :event_type, null: false  # birth, training_started, training_completed, maturation, promotion, demotion, retirement, resurrection
      
      # Event details
      t.text :description
      t.jsonb :event_data, default: {}
      
      # Metrics at time of event (from EvolutionService)
      t.jsonb :metrics_snapshot, default: {}
      
      # Related agents (for birth: parent agents; for retirement: successor)
      t.jsonb :related_agents, default: []
      
      # Triggering context - links to other systems
      t.string :triggered_by  # desire_engine, user_request, evolution_cycle, system_detection, agent_school
      t.references :triggered_by_goal, null: true, foreign_key: { to_table: :agent_goals }
      t.references :school_enrollment, null: true, foreign_key: { to_table: :agent_school_enrollments }
      
      t.timestamps
    end
    
    add_index :agent_lifecycle_events, [:agent_plugin_id, :event_type]
    add_index :agent_lifecycle_events, [:entity_id, :event_type]
    add_index :agent_lifecycle_events, :created_at
    
    # Global knowledge archive (for retired agents' knowledge, shared learnings)
    create_table :global_knowledge_archives do |t|
      t.references :entity, null: false, foreign_key: true
      
      # Source
      t.string :source_agent_slug
      t.string :source_agent_name
      t.string :source_type  # agent_retirement, manual_archive, knowledge_graduation, evolution_learning
      
      # Knowledge content
      t.string :title, null: false
      t.text :content
      t.string :knowledge_type  # technique, pattern, prompt_template, tool_usage, domain_expertise
      
      # Relevance
      t.jsonb :applicable_domains, default: []
      t.jsonb :applicable_capabilities, default: []
      t.decimal :utility_score, precision: 5, scale: 4
      
      # Usage tracking
      t.integer :times_accessed, default: 0
      t.integer :times_applied, default: 0
      t.datetime :last_accessed_at
      
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    add_index :global_knowledge_archives, [:entity_id, :knowledge_type]
    add_index :global_knowledge_archives, :source_agent_slug
    
    # ═══════════════════════════════════════════════════════════════════════════
    # EXTENSIONS TO EXISTING TABLES
    # ═══════════════════════════════════════════════════════════════════════════

    # Add lifecycle fields to agent_plugins (check for existing columns)
    add_column :agent_plugins, :lifecycle_stage, :string, default: 'active' unless column_exists?(:agent_plugins, :lifecycle_stage)
    add_column :agent_plugins, :generation, :integer, default: 1 unless column_exists?(:agent_plugins, :generation)
    add_column :agent_plugins, :birth_reason, :text unless column_exists?(:agent_plugins, :birth_reason)
    add_column :agent_plugins, :parent_agent_ids, :jsonb, default: [] unless column_exists?(:agent_plugins, :parent_agent_ids)
    add_column :agent_plugins, :discovered_specializations, :jsonb, default: [] unless column_exists?(:agent_plugins, :discovered_specializations)
    add_column :agent_plugins, :last_reflection_at, :datetime unless column_exists?(:agent_plugins, :last_reflection_at)
    add_column :agent_plugins, :last_evolution_at, :datetime unless column_exists?(:agent_plugins, :last_evolution_at)
    add_column :agent_plugins, :evolution_count, :integer, default: 0 unless column_exists?(:agent_plugins, :evolution_count)
    add_column :agent_plugins, :autonomous_goals_enabled, :boolean, default: true unless column_exists?(:agent_plugins, :autonomous_goals_enabled)

    add_index :agent_plugins, :lifecycle_stage unless index_exists?(:agent_plugins, :lifecycle_stage)
    add_index :agent_plugins, :generation unless index_exists?(:agent_plugins, :generation)

    # Add evolution tracking to agent_plugin_executions
    unless column_exists?(:agent_plugin_executions, :evolution_experiment_id)
      add_reference :agent_plugin_executions, :evolution_experiment, 
                    foreign_key: { to_table: :agent_ab_tests }, null: true
    end
    add_column :agent_plugin_executions, :is_experiment_control, :boolean unless column_exists?(:agent_plugin_executions, :is_experiment_control)
    add_column :agent_plugin_executions, :reflection_generated, :boolean, default: false unless column_exists?(:agent_plugin_executions, :reflection_generated)

    # Link AgentSchoolEnrollment to goals and lifecycle
    unless column_exists?(:agent_school_enrollments, :triggered_by_goal_id)
      add_reference :agent_school_enrollments, :triggered_by_goal, 
                    foreign_key: { to_table: :agent_goals }, null: true
    end
    unless column_exists?(:agent_school_enrollments, :evolution_cycle_id)
      add_reference :agent_school_enrollments, :evolution_cycle,
                    foreign_key: true, null: true
    end
  end
end
