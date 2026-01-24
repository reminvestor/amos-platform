# frozen_string_literal: true

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           ⚠️ DEPRECATED ⚠️                                  ║
# ╠════════════════════════════════════════════════════════════════════════════╣
# ║ This file is DEPRECATED as of 2026-01-24.                                   ║
# ║                                                                             ║
# ║ With the Plugin Injection architecture, agents are now "loadouts" that     ║
# ║ enhance Amos directly. There's no need for:                                 ║
# ║ - Agent enrollment/graduation ceremonies                                    ║
# ║ - Student variants                                                          ║
# ║ - Complex A/B testing between agent versions                                ║
# ║                                                                             ║
# ║ REPLACEMENT:                                                                ║
# ║ - LoadoutOptimizationService - for tracking and auto-optimizing loadouts    ║
# ║ - LoadoutHealthMonitor - for monitoring loadout health                       ║
# ║ - LoadoutVersion - for tracking prompt/tool changes                          ║
# ║                                                                             ║
# ║ DO NOT USE THIS FILE FOR NEW CODE.                                          ║
# ╚════════════════════════════════════════════════════════════════════════════╝

module Collaboration
  class AgentSchool
    MAX_RETRY_ATTEMPTS = 3
    GRADUATION_TEST_TASKS = 50
    SIGNIFICANCE_THRESHOLD = 0.05

    def initialize
      @pricer = DynamicEnergyPricer.new
    end

    # ============================================
    # ENROLLMENT
    # ============================================

    def enroll(agent)
      return { error: 'Agent has energy' } if agent.current_energy > 0
      return { error: 'Agent already in school' } if agent.in_school?

      Rails.logger.info "[AgentSchool] Enrolling agent #{agent.id} (#{agent.name})"

      enrollment = nil

      ActiveRecord::Base.transaction do
        # Create enrollment record
        enrollment = AgentSchoolEnrollment.create!(
          agent_plugin: agent,
          entity: agent.entity,
          status: 'enrolled',
          enrollment_reason: 'zero_energy',
          attempt_number: previous_attempt_count(agent) + 1
        )

        # Suspend agent
        agent.update!(status: 'in_school', school_enrollment: enrollment)
      end

      # Run diagnosis asynchronously
      AgentSchoolDiagnosisJob.perform_later(enrollment.id)

      { success: true, enrollment: enrollment }
    end

    # ============================================
    # DIAGNOSIS
    # ============================================

    def diagnose(enrollment)
      agent = enrollment.agent_plugin
      enrollment.start_diagnosis!

      Rails.logger.info "[AgentSchool] Diagnosing agent #{agent.name}"

      # Collect failures
      failures = agent.agent_plugin_executions
        .where(status: 'failed')
        .where('created_at > ?', 30.days.ago)
        .order(created_at: :desc)

      diagnosis = {
        total_failures: failures.count,
        failure_by_task_type: analyze_failure_by_task_type(failures),
        failure_by_tool: analyze_failure_by_tool(failures),
        collaboration_gaps: find_collaboration_gaps(failures, agent),
        overconfidence_areas: find_overconfidence_areas(agent),
        comparison_to_peers: compare_to_peers(agent),
        root_causes: [],
        prescription: {}
      }

      # Identify root causes
      diagnosis[:root_causes] = identify_root_causes(diagnosis)

      # Generate prescription
      diagnosis[:prescription] = generate_prescription(diagnosis)

      enrollment.complete_diagnosis!(diagnosis)

      # Create student and apply curriculum
      student = create_student(agent, enrollment)
      apply_curriculum(student, diagnosis, enrollment)

      { success: true, diagnosis: diagnosis, student: student }
    end

    # ============================================
    # CURRICULUM
    # ============================================

    def apply_curriculum(student, diagnosis, enrollment)
      curriculum_applied = []

      # Module 1: Prompt Refinement
      if diagnosis[:failure_by_task_type].any?
        changes = apply_prompt_refinement(student, diagnosis)
        curriculum_applied << { module: 'prompt_refinement', changes: changes }
      end

      # Module 2: Tool Assignment Review
      if diagnosis[:failure_by_tool].any?
        changes = apply_tool_review(student, diagnosis)
        curriculum_applied << { module: 'tool_assignment', changes: changes }
      end

      # Module 3: Capability Recalibration
      if diagnosis[:overconfidence_areas].any?
        changes = apply_capability_recalibration(student, diagnosis)
        curriculum_applied << { module: 'capability_recalibration', changes: changes }
      end

      # Module 4: Decision Boundary Adjustment
      if diagnosis[:collaboration_gaps].any?
        changes = apply_decision_boundary_adjustment(student, diagnosis)
        curriculum_applied << { module: 'decision_boundary', changes: changes }
      end

      enrollment.complete_curriculum!(curriculum_applied)

      # Start graduation test
      start_graduation_test(enrollment.agent_plugin, student, enrollment)

      curriculum_applied
    end

    # ============================================
    # GRADUATION
    # ============================================

    def evaluate_graduation(enrollment)
      test = enrollment.graduation_test
      return { error: 'Test not complete' } unless test&.completed?

      comparison = test.statistical_analysis

      if test.variant_significantly_better?
        graduate(enrollment, comparison)
      elsif test.no_significant_difference?
        if enrollment.can_retry?
          retry_school(enrollment, comparison)
        else
          handle_failed_graduation(enrollment, comparison)
        end
      else
        handle_failed_graduation(enrollment, comparison)
      end
    end

    private

    # ============================================
    # ANALYSIS HELPERS
    # ============================================

    def analyze_failure_by_task_type(failures)
      result = {}

      failures.each do |execution|
        task_type = classify_task_type(execution)
        result[task_type] ||= { count: 0, examples: [] }
        result[task_type][:count] += 1

        if result[task_type][:examples].size < 3
          result[task_type][:examples] << {
            task: execution.input_context&.dig('task_description')&.to_s&.truncate(100),
            error: extract_error_message(execution)&.truncate(200)
          }
        end
      end

      result
    end

    def analyze_failure_by_tool(failures)
      result = {}

      failures.each do |execution|
        # Use input_context instead of metadata (which doesn't exist on AgentPluginExecution)
        tools_used = execution.input_context&.dig('tools_used') || []
        tool_errors = execution.output_result&.dig('tool_errors') || {}

        tools_used.each do |tool|
          if tool_errors[tool].present?
            result[tool] ||= { count: 0, errors: [] }
            result[tool][:count] += 1
            result[tool][:errors] << tool_errors[tool]
          end
        end
      end

      result
    end

    def find_collaboration_gaps(failures, agent)
      gaps = []

      failures.each do |execution|
        # Check if agent had low confidence but didn't ask for help
        # Use input_context instead of metadata
        confidence = execution.input_context&.dig('energy_tracking', 'confidence_at_start')
        asked_for_help = agent.collaboration_requests_made
          .where(agent_plugin_execution: execution)
          .exists?

        if confidence.present? && confidence < 60 && !asked_for_help
          gaps << {
            execution_id: execution.id,
            task: execution.input_context&.dig('task_description')&.to_s&.truncate(100),
            confidence: confidence,
            suggestion: 'Should have asked for help'
          }
        end
      end

      gaps
    end

    def find_overconfidence_areas(agent)
      areas = []

      agent.capability_beliefs.each do |belief|
        # High confidence but low actual success
        if belief.attempts >= 5 && belief.success_rate < 0.5
          areas << {
            task_type: belief.task_type,
            success_rate: belief.success_rate,
            attempts: belief.attempts
          }
        end
      end

      areas
    end

    def compare_to_peers(agent)
      peers = AgentPlugin.active
        .where(entity: agent.entity)
        .where(role: agent.role)
        .where.not(id: agent.id)
        .limit(5)

      comparison = {}

      peers.each do |peer|
        peer_state = peer.energy_state
        next unless peer_state

        comparison[peer.id] = {
          name: peer.name,
          success_rate: peer_state.success_rate,
          avg_quality: peer_state.avg_quality,
          tasks_completed: peer_state.tasks_completed
        }
      end

      comparison
    end

    def identify_root_causes(diagnosis)
      causes = []

      # High failure rate on specific task types
      diagnosis[:failure_by_task_type].each do |task_type, data|
        if data[:count] >= 3
          causes << {
            type: :task_type_weakness,
            task_type: task_type,
            failure_count: data[:count]
          }
        end
      end

      # Tool failures
      diagnosis[:failure_by_tool].each do |tool, data|
        if data[:count] >= 2
          causes << {
            type: :tool_failure,
            tool: tool,
            failure_count: data[:count]
          }
        end
      end

      # Collaboration gaps
      if diagnosis[:collaboration_gaps].size >= 3
        causes << {
          type: :insufficient_collaboration,
          gap_count: diagnosis[:collaboration_gaps].size
        }
      end

      causes
    end

    def generate_prescription(diagnosis)
      prescription = {
        modules_needed: [],
        priority: 'medium'
      }

      if diagnosis[:failure_by_task_type].any?
        prescription[:modules_needed] << 'prompt_refinement'
      end

      if diagnosis[:failure_by_tool].any?
        prescription[:modules_needed] << 'tool_assignment'
      end

      if diagnosis[:overconfidence_areas].any?
        prescription[:modules_needed] << 'capability_recalibration'
      end

      if diagnosis[:collaboration_gaps].any?
        prescription[:modules_needed] << 'decision_boundary'
        prescription[:priority] = 'high'  # Collaboration issues are critical
      end

      prescription
    end

    # ============================================
    # CURRICULUM MODULES
    # ============================================

    def apply_prompt_refinement(student, diagnosis)
      # Use AI to refine the prompt based on failure patterns
      current_prompt = student.system_prompt

      refinement_request = <<~PROMPT
        Analyze this agent's system prompt and suggest improvements based on failure patterns.

        CURRENT PROMPT:
        #{current_prompt.to_json}

        FAILURE PATTERNS BY TASK TYPE:
        #{diagnosis[:failure_by_task_type].to_json}

        ROOT CAUSES:
        #{diagnosis[:root_causes].to_json}

        Please provide an improved system prompt that:
        1. Adds guardrails for the identified failure modes
        2. Encourages asking for help when confidence is low
        3. Provides clearer guidance for problematic task types

        Return the improved prompt as JSON.
      PROMPT

      # For now, add basic guardrails
      improved_prompt = current_prompt.dup
      improved_prompt['guardrails'] ||= []
      improved_prompt['guardrails'] << "When confidence is below 60%, consider asking for help before proceeding."
      improved_prompt['guardrails'] << "For complex tasks, break them into smaller steps and validate each step."

      student.update!(system_prompt: improved_prompt)

      { original: current_prompt, improved: improved_prompt }
    end

    def apply_tool_review(student, diagnosis)
      changes = { removed: [], added: [] }

      # Remove tools with high failure rates
      diagnosis[:failure_by_tool].each do |tool, data|
        if data[:count] >= 3
          student.agent_tools.where(tool_name: tool).destroy_all
          changes[:removed] << tool
        end
      end

      changes
    end

    def apply_capability_recalibration(student, diagnosis)
      changes = []

      diagnosis[:overconfidence_areas].each do |area|
        belief = student.capability_beliefs.find_by(task_type: area[:task_type])
        next unless belief

        # Reset confidence
        old_values = { avg_quality: belief.avg_quality }
        belief.update!(avg_quality: 0.5, is_specialty: false)

        changes << {
          task_type: area[:task_type],
          old_values: old_values,
          new_values: { avg_quality: 0.5 }
        }
      end

      changes
    end

    def apply_decision_boundary_adjustment(student, diagnosis)
      boundary = student.ensure_decision_boundary!

      old_values = {
        ask_alpha: boundary.ask_alpha,
        ask_beta: boundary.ask_beta
      }

      # Increase tendency to ask for help
      gap_count = diagnosis[:collaboration_gaps].size
      boundary.ask_alpha += gap_count * 2
      boundary.solo_beta += gap_count
      boundary.save!

      {
        old_values: old_values,
        new_values: {
          ask_alpha: boundary.ask_alpha,
          ask_beta: boundary.ask_beta
        },
        reason: "#{gap_count} collaboration gaps identified"
      }
    end

    # ============================================
    # STUDENT CREATION
    # ============================================

    def create_student(original, enrollment)
      student = original.dup
      student.name = "#{original.name} (Student v#{enrollment.attempt_number})"
      student.slug = "#{original.slug}_student_#{enrollment.attempt_number}"
      student.status = 'testing'
      student.parent_agent = original
      student.generation = (original.generation || 1) + 1
      student.school_enrollment = enrollment
      student.save!

      # Create fresh energy state
      AgentEnergyState.create!(
        agent_plugin: student,
        entity: student.entity,
        current_energy: 30
      )

      # Copy decision boundary
      if original.decision_boundary
        boundary = original.decision_boundary.dup
        boundary.agent_plugin = student
        boundary.save!
      end

      enrollment.update!(student_agent: student)

      student
    end

    # ============================================
    # GRADUATION TEST
    # ============================================

    def start_graduation_test(original, student, enrollment)
      test = AgentAbTest.create!(
        control_agent: original,
        variant_agent: student,
        entity: original.entity,
        enrollment: enrollment,
        status: 'running',
        target_tasks: GRADUATION_TEST_TASKS,
        started_at: Time.current
      )

      enrollment.start_testing!(test)

      test
    end

    # ============================================
    # GRADUATION OUTCOMES
    # ============================================

    def graduate(enrollment, comparison)
      Rails.logger.info "[AgentSchool] 🎓 Agent #{enrollment.agent_plugin.name} GRADUATED!"

      original = enrollment.agent_plugin
      student = enrollment.student_agent

      ActiveRecord::Base.transaction do
        # Archive original
        original.update!(
          status: 'archived',
          school_enrollment: nil
        )

        # Promote student
        student.update!(
          status: 'active',
          name: original.name,
          slug: original.slug,
          school_enrollment: nil,
          graduated_at: Time.current
        )

        # Give graduate fresh energy
        student.energy_state.update!(current_energy: 50)

        # Transfer relationships
        AgentRelationship.inherit_from!(original, student)

        enrollment.graduate!(comparison)
      end

      { outcome: :graduated, new_agent: student }
    end

    def retry_school(enrollment, comparison)
      Rails.logger.info "[AgentSchool] 🔄 Agent #{enrollment.agent_plugin.name} retrying school"

      enrollment.retry!(comparison)

      # Archive student
      enrollment.student_agent&.update!(status: 'archived')

      # Re-enroll original
      original = enrollment.agent_plugin
      original.update!(status: 'active')  # Temporarily active to re-enroll
      original.energy_state&.update!(current_energy: 0)

      # Trigger new enrollment
      AgentSchoolEnrollmentJob.perform_later(original.id)

      { outcome: :retry, attempt: enrollment.attempt_number + 1 }
    end

    def handle_failed_graduation(enrollment, comparison)
      original = enrollment.agent_plugin

      # Check irreplaceability
      irreplaceability = assess_irreplaceability(original)

      if irreplaceability[:is_irreplaceable]
        probation(enrollment, comparison, irreplaceability)
      else
        expel(enrollment, comparison)
      end
    end

    def assess_irreplaceability(agent)
      result = {
        is_irreplaceable: false,
        reasons: [],
        replacement_difficulty: 0.0
      }

      # Check for unique capabilities
      agent.capability_names.each do |cap|
        others = AgentPlugin.available
          .where(entity: agent.entity)
          .where.not(id: agent.id)
          .joins(:agent_capabilities)
          .where(agent_capabilities: { capability_name: cap })

        if others.empty?
          result[:reasons] << { type: :unique_capability, capability: cap, severity: :high }
          result[:replacement_difficulty] += 0.4
        end
      end

      # Check for exclusive task type coverage
      agent.capability_beliefs.where(is_specialty: true).each do |belief|
        others = AgentPlugin.available
          .where(entity: agent.entity)
          .where.not(id: agent.id)
          .joins(:capability_beliefs)
          .where(agent_capability_beliefs: { task_type: belief.task_type, is_specialty: true })

        if others.empty?
          result[:reasons] << { type: :exclusive_task_coverage, task_type: belief.task_type, severity: :high }
          result[:replacement_difficulty] += 0.3
        end
      end

      # Check institutional knowledge
      if agent.total_tasks > 500 && agent.lifetime_success_rate > 0.5
        result[:reasons] << { type: :institutional_knowledge, tasks: agent.total_tasks, severity: :medium }
        result[:replacement_difficulty] += 0.1
      end

      result[:is_irreplaceable] = result[:replacement_difficulty] > 0.5 ||
        result[:reasons].any? { |r| r[:severity] == :high }

      result
    end

    def probation(enrollment, comparison, irreplaceability)
      Rails.logger.info "[AgentSchool] ⚠️ Agent #{enrollment.agent_plugin.name} on PROBATION"

      original = enrollment.agent_plugin
      student = enrollment.student_agent

      # Keep better version
      better = comparison.dig('metrics', 'quality', 'variant_better') ? student : original
      worse = better == student ? original : student

      ActiveRecord::Base.transaction do
        worse.update!(status: 'archived')

        better.update!(
          status: 'probation',
          probation_started_at: Time.current,
          probation_reasons: irreplaceability[:reasons],
          priority_score: calculate_probation_priority(better, irreplaceability),
          school_enrollment: nil
        )

        better.energy_state&.update!(current_energy: 20)

        enrollment.probation!(comparison, irreplaceability)
      end

      # Schedule replacement training if possible
      if irreplaceability[:replacement_difficulty] < 0.8
        ReplacementTrainingJob.perform_later(better.id)
      end

      { outcome: :probation, agent: better }
    end

    def expel(enrollment, comparison)
      Rails.logger.info "[AgentSchool] ❌ Agent #{enrollment.agent_plugin.name} EXPELLED"

      original = enrollment.agent_plugin
      student = enrollment.student_agent

      ActiveRecord::Base.transaction do
        original.update!(status: 'deprecated')
        student&.update!(status: 'deprecated')
        enrollment.expel!(comparison)
      end

      # Create replacement
      replacement = create_replacement_agent(original)

      { outcome: :expelled, replacement: replacement }
    end

    def calculate_probation_priority(agent, irreplaceability)
      base = 0.3

      if irreplaceability[:reasons].any? { |r| r[:type] == :unique_capability }
        base += 0.3
      end

      if agent.lifetime_success_rate > 0.7
        base += 0.2
      end

      base.clamp(0.1, 0.8)
    end

    def create_replacement_agent(original)
      # Create a new agent based on the original's role
      replacement = AgentPlugin.create!(
        name: "#{original.role.titleize} Agent (Replacement)",
        slug: "#{original.slug}_replacement_#{Time.current.to_i}",
        role: original.role,
        entity: original.entity,
        status: 'active',
        description: original.description,
        system_prompt: original.system_prompt,
        configuration: original.configuration,
        generation: 1,
        parent_agent: original
      )

      # Create energy state
      AgentEnergyState.create!(
        agent_plugin: replacement,
        entity: replacement.entity,
        current_energy: 50
      )

      replacement
    end

    def previous_attempt_count(agent)
      AgentSchoolEnrollment.where(agent_plugin: agent).count
    end

    def classify_task_type(execution)
      # Use input_context instead of input (which doesn't exist on AgentPluginExecution)
      task = execution.input_context&.dig('task_description') || ''
      task = task.to_s.downcase

      if task.include?('analyze') || task.include?('analysis')
        'analysis'
      elsif task.include?('create') || task.include?('generate')
        'creation'
      elsif task.include?('research') || task.include?('find')
        'research'
      else
        'general'
      end
    end

    def extract_error_message(execution)
      # AgentPluginExecution stores errors in output_result
      execution.output_result&.dig('error') ||
        execution.output_result&.dig('error_message') ||
        execution.output_result&.dig('message') ||
        'Unknown error'
    end
  end
end

