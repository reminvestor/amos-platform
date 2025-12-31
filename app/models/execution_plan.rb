# frozen_string_literal: true

# ExecutionPlan - Structured plan for complex multi-step tasks
#
# Created by the Planner agent, executed by Amos with help from specialized agents.
# Tracks phases, steps, dependencies, and progress.
#
class ExecutionPlan < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  belongs_to :created_by_agent, class_name: 'AgentPlugin', optional: true

  # Status progression
  STATUSES = %w[planning ready executing paused completed failed cancelled].freeze
  COMPLEXITIES = %w[simple medium complex epic].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :complexity, inclusion: { in: COMPLEXITIES }
  validates :title, presence: true
  validates :original_request, presence: true

  # Scopes
  scope :active, -> { where(status: %w[planning ready executing paused]) }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :for_user, ->(user) { where(user: user) }
  scope :recent, -> { order(created_at: :desc) }

  # ============================================
  # PLAN STRUCTURE
  # ============================================
  
  # phases structure:
  # [
  #   {
  #     id: "phase_1",
  #     name: "Discovery",
  #     description: "Understand user requirements",
  #     status: "pending", # pending, in_progress, completed, failed, skipped
  #     steps: [
  #       {
  #         id: "step_1_1",
  #         name: "Gather requirements",
  #         description: "...",
  #         agent: "module_architect",
  #         tools_needed: ["ask_user", "get_data"],
  #         status: "pending",
  #         result: nil,
  #         dependencies: [], # step IDs that must complete first
  #         estimated_minutes: 5
  #       }
  #     ]
  #   }
  # ]

  # ============================================
  # LIFECYCLE METHODS
  # ============================================

  def mark_ready!(auto_execute: true)
    update!(status: 'ready')
    log_event('plan_ready', 'Plan validated and ready for execution')
    
    # Auto-trigger execution if enabled
    if auto_execute
      Rails.logger.info "[ExecutionPlan] 🚀 AUTO-EXECUTING plan ##{id}: #{title}"
      Rails.logger.info "[ExecutionPlan] Queueing PlanExecutorJob..."
      PlanExecutorJob.perform_later(id)
      Rails.logger.info "[ExecutionPlan] PlanExecutorJob queued successfully!"
    else
      Rails.logger.info "[ExecutionPlan] Plan ##{id} ready but auto_execute=false"
    end
  end

  def start_execution!
    update!(
      status: 'executing',
      started_at: Time.current,
      current_phase: 0
    )
    log_event('execution_started', 'Plan execution started')
    hub_bridge.on_plan_started
  end

  def pause!(reason: nil)
    update!(status: 'paused')
    log_event('execution_paused', reason || 'Execution paused')
    hub_bridge.on_plan_paused(reason)
  end

  def resume!
    update!(status: 'executing')
    log_event('execution_resumed', 'Execution resumed')
    hub_bridge.on_plan_resumed
  end

  def complete!
    update!(
      status: 'completed',
      completed_at: Time.current,
      actual_duration_minutes: calculate_duration
    )
    log_event('plan_completed', 'All steps completed successfully')
    hub_bridge.on_plan_completed
    create_completion_work_item
  end

  def fail!(reason:)
    update!(
      status: 'failed',
      failed_at: Time.current,
      failure_reason: reason,
      actual_duration_minutes: calculate_duration
    )
    log_event('plan_failed', reason)
    hub_bridge.on_plan_failed(reason)
  end

  def cancel!
    update!(status: 'cancelled')
    log_event('plan_cancelled', 'Plan cancelled by user')
  end

  def approve!
    update!(
      approved: true,
      approved_at: Time.current
    )
    log_event('plan_approved', 'Plan approved by user')
  end

  # ============================================
  # PHASE/STEP MANAGEMENT
  # ============================================

  def current_phase_data
    phases[current_phase] if phases.present? && current_phase < phases.length
  end

  def next_step
    return nil unless current_phase_data

    # Find pending steps first
    pending = current_phase_data['steps']&.find { |s| s['status'] == 'pending' }
    return pending if pending
    
    # Also check for in_progress steps that may be stalled (no active execution)
    in_progress = current_phase_data['steps']&.find { |s| s['status'] == 'in_progress' }
    return nil unless in_progress
    
    # Check if there's an active execution for this step
    active_exec = AgentPluginExecution
      .where(status: 'running')
      .where("input_context->>'step_id' = ?", in_progress['id'])
      .exists?
    
    # Return the stalled step if no active execution
    active_exec ? nil : in_progress
  end

  def all_steps
    phases.flat_map { |phase| phase['steps'] || [] }
  end
  
  def all_steps_completed?
    all_steps.all? { |s| s['status'].in?(%w[completed skipped]) }
  end
  
  def pending_steps
    all_steps.select { |s| s['status'] == 'pending' }
  end

  def find_step(step_id)
    all_steps.find { |s| s['id'] == step_id }
  end

  def step_ready?(step_id)
    step = find_step(step_id)
    return false unless step

    dependencies = step['dependencies'] || []
    return true if dependencies.empty?

    # Check all dependencies are completed
    dependencies.all? do |dep_id|
      dep_step = find_step(dep_id)
      dep_step && dep_step['status'] == 'completed'
    end
  end

  def mark_step_started!(step_id)
    step = find_step(step_id)
    update_step(step_id, 'status' => 'in_progress', 'started_at' => Time.current.iso8601)
    update!(current_step_id: step_id)
    log_event('step_started', "Started: #{step['name']}")
    hub_bridge.on_step_started(step)
  end

  def mark_step_completed!(step_id, result: nil)
    step = find_step(step_id)
    update_step(step_id, 
      'status' => 'completed', 
      'completed_at' => Time.current.iso8601,
      'result' => result
    )
    
    increment!(:completed_steps)
    log_event('step_completed', "Completed: #{step['name']}")
    hub_bridge.on_step_completed(step, result)
    create_step_work_item(step, result)
    
    # Check if phase is complete
    check_phase_completion
  end

  def mark_step_failed!(step_id, error:, auto_recover: true)
    step = find_step(step_id)
    update_step(step_id, 
      'status' => 'failed', 
      'failed_at' => Time.current.iso8601,
      'error' => error
    )
    
    increment!(:failed_steps)
    log_event('step_failed', "Failed: #{step['name']} - #{error}")
    hub_bridge.on_step_failed(step, error)

    # Trigger automatic recovery if enabled
    if auto_recover
      PlanAutoRecoveryJob.perform_later(id, step_id, error)
    end
  end

  def skip_step!(step_id, reason: nil)
    update_step(step_id, 
      'status' => 'skipped', 
      'skipped_at' => Time.current.iso8601,
      'skip_reason' => reason
    )
    log_event('step_skipped', "Skipped: #{find_step(step_id)['name']}")
  end

  # ============================================
  # PROGRESS TRACKING
  # ============================================

  def progress_percentage
    return 0 if total_steps.zero?
    ((completed_steps.to_f / total_steps) * 100).round
  end

  def phase_progress
    phases.map.with_index do |phase, idx|
      steps = phase['steps'] || []
      completed = steps.count { |s| s['status'] == 'completed' }
      {
        index: idx,
        name: phase['name'],
        total: steps.count,
        completed: completed,
        status: phase['status'],
        is_current: idx == current_phase
      }
    end
  end

  def blocking_steps
    all_steps.select { |s| s['status'] == 'failed' || (s['status'] == 'pending' && !step_ready?(s['id'])) }
  end

  # ============================================
  # AGENT ASSIGNMENTS
  # ============================================

  def agent_for_step(step_id)
    step = find_step(step_id)
    step&.dig('agent') || agent_assignments[step_id]
  end

  def steps_for_agent(agent_slug)
    all_steps.select { |s| s['agent'] == agent_slug }
  end

  def validate_assignments!
    results = {}
    
    all_steps.each do |step|
      agent_slug = step['agent']
      next unless agent_slug

      agent = AgentPlugin.find_by(slug: agent_slug, status: 'active')
      
      if agent
        # Use handshake protocol to validate
        proposal = AgentTaskProposal.new(
          receiving_agent: agent,
          entity: entity,
          task_description: step['description'] || step['name'],
          tools_needed: step['tools_needed'] || []
        )
        
        evaluation = proposal.evaluate_capability
        results[step['id']] = {
          agent: agent_slug,
          valid: evaluation[:accepted],
          confidence: evaluation[:confidence],
          issues: evaluation[:accepted] ? [] : [evaluation[:reason]]
        }
      else
        results[step['id']] = {
          agent: agent_slug,
          valid: false,
          confidence: 0,
          issues: ["Agent '#{agent_slug}' not found"]
        }
      end
    end

    update!(validation_results: results)
    results.values.all? { |r| r[:valid] }
  end

  # ============================================
  # SERIALIZATION
  # ============================================

  def to_summary
    {
      id: id,
      title: title,
      status: status,
      complexity: complexity,
      progress: progress_percentage,
      total_steps: total_steps,
      completed_steps: completed_steps,
      current_phase: current_phase_data&.dig('name'),
      current_step: find_step(current_step_id)&.dig('name'),
      requires_approval: requires_approval,
      approved: approved,
      estimated_minutes: estimated_duration_minutes,
      started_at: started_at,
      blocking: blocking_steps.count
    }
  end

  def to_detailed
    to_summary.merge(
      original_request: original_request,
      summary: summary,
      phases: phase_progress,
      all_steps: all_steps.map { |s|
        {
          id: s['id'],
          name: s['name'],
          status: s['status'],
          agent: s['agent'],
          phase: phases.find { |p| p['steps']&.include?(s) }&.dig('name')
        }
      },
      execution_log: execution_log.last(10),
      validation_results: validation_results
    )
  end

  # Hub integration
  def hub_bridge
    @hub_bridge ||= Hub::PlanBridgeService.new(plan: self)
  end

  private

  # Create work item for completed step
  def create_step_work_item(step, result)
    return unless user && entity

    AgentWorkItem.create!(
      entity: entity,
      user: user,
      work_type: 'task_completed',
      title: "Plan step completed: #{step['name']}",
      description: "Step '#{step['name']}' in plan '#{title}' has completed.",
      priority: 'normal',
      result_summary: result.to_s.truncate(500),
      metadata: {
        plan_id: id,
        plan_title: title,
        step_id: step['id'],
        step_name: step['name'],
        agent: step['agent']
      }
    )
  rescue => e
    Rails.logger.warn "[ExecutionPlan] Failed to create step work item: #{e.message}"
  end

  # Create work item for completed plan
  def create_completion_work_item
    return unless user && entity

    AgentWorkItem.create!(
      entity: entity,
      user: user,
      work_type: 'task_completed',
      title: "Plan completed: #{title}",
      description: "Your plan '#{title}' has completed successfully with #{completed_steps} steps in #{actual_duration_minutes || 0} minutes.",
      priority: 'high',
      result_summary: summary || original_request.truncate(200),
      metadata: {
        plan_id: id,
        plan_title: title,
        total_steps: total_steps,
        completed_steps: completed_steps,
        duration_minutes: actual_duration_minutes
      }
    )
  rescue => e
    Rails.logger.warn "[ExecutionPlan] Failed to create completion work item: #{e.message}"
  end

  def update_step(step_id, updates)
    updated_phases = phases.map do |phase|
      updated_steps = (phase['steps'] || []).map do |step|
        if step['id'] == step_id
          step.merge(updates)
        else
          step
        end
      end
      phase.merge('steps' => updated_steps)
    end
    
    update!(phases: updated_phases)
  end

  def check_phase_completion
    return unless current_phase_data

    all_complete = current_phase_data['steps']&.all? { |s| %w[completed skipped].include?(s['status']) }
    
    if all_complete
      # Mark phase complete
      updated_phases = phases.dup
      updated_phases[current_phase]['status'] = 'completed'
      
      # Move to next phase
      next_phase = current_phase + 1
      
      if next_phase < phases.length
        updated_phases[next_phase]['status'] = 'in_progress'
        update!(phases: updated_phases, current_phase: next_phase)
        log_event('phase_completed', "Phase '#{current_phase_data['name']}' completed, starting next phase")
      else
        update!(phases: updated_phases)
        complete!
      end
    end
  end

  def log_event(event_type, message)
    new_log = execution_log + [{
      timestamp: Time.current.iso8601,
      event: event_type,
      message: message
    }]
    update_column(:execution_log, new_log)
  end

  def calculate_duration
    return nil unless started_at
    ((Time.current - started_at) / 60).round
  end
end

