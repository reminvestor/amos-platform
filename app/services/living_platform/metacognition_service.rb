# frozen_string_literal: true

module LivingPlatform
  # MetacognitionService - Agent Self-Awareness
  #
  # Enables agents to reflect on their own performance and identify areas
  # for improvement. This creates a feedback loop where agents can learn
  # from their experiences without external intervention.
  #
  # Reflection Types:
  # - execution: After each task completion
  # - daily: End-of-day summary
  # - weekly: Weekly performance review
  # - triggered: When performance drops or issues detected
  #
  # Integration:
  # - Creates AgentReflection records
  # - Can trigger AgentSchool enrollment for significant issues
  # - Feeds into DesireEngine for learning goals
  # - Uses EvolutionService for peer comparison
  #
  class MetacognitionService
    attr_reader :agent

    # Configuration
    REFLECTION_SAMPLE_RATE = 0.3  # 30% of executions get reflection
    MIN_EXECUTIONS_FOR_COMPARISON = 10
    CRITICAL_SCORE_THRESHOLD = 4
    
    def initialize(agent)
      @agent = agent
      @entity = agent.entity
      @evolution_service = Agents::EvolutionService.new(entity: @entity)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # EXECUTION REFLECTION
    # Called after task completion to reflect on performance
    # ═══════════════════════════════════════════════════════════════════════════

    def reflect_on_execution(execution)
      return nil unless should_reflect?(execution)
      
      Rails.logger.info "[Metacognition] Agent #{agent.name} reflecting on execution #{execution.id}"
      
      # Get AI self-assessment
      assessment = get_ai_self_assessment(execution)
      
      # Identify issues and improvements
      issues = identify_issues(execution, assessment)
      improvements = generate_improvement_ideas(execution, assessment, issues)
      knowledge_gaps = identify_knowledge_gaps(execution, assessment)
      
      # Create reflection record
      reflection = AgentReflection.create!(
        entity: @entity,
        agent_plugin: agent,
        agent_plugin_execution: execution,
        reflection_type: 'execution',
        efficiency_score: assessment[:efficiency],
        quality_score: assessment[:quality],
        tool_usage_score: assessment[:tool_usage],
        communication_score: assessment[:communication],
        overall_score: calculate_overall_score(assessment),
        identified_issues: issues,
        improvement_ideas: improvements,
        knowledge_gaps: knowledge_gaps,
        strengths_identified: assessment[:strengths] || [],
        raw_reflection: assessment[:raw_text]
      )
      
      reflection.update_overall_score!
      
      # Mark execution as reflected
      execution.update!(reflection_generated: true)
      
      # Update agent's last reflection timestamp
      agent.update!(last_reflection_at: Time.current)
      
      # Handle critical issues
      if reflection.has_critical_issues? || reflection.overall_score.to_i <= CRITICAL_SCORE_THRESHOLD
        schedule_improvement_actions(reflection)
      end
      
      reflection
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # DAILY REFLECTION
    # End-of-day summary of performance
    # ═══════════════════════════════════════════════════════════════════════════

    def daily_reflection
      Rails.logger.info "[Metacognition] Agent #{agent.name} performing daily reflection"
      
      # Get today's executions
      executions = agent.agent_plugin_executions
        .where('created_at > ?', 24.hours.ago)
      
      return nil if executions.empty?
      
      # Aggregate performance
      completed = executions.where(status: 'completed').count
      failed = executions.where(status: 'failed').count
      total = completed + failed
      success_rate = total > 0 ? (completed.to_f / total * 100).round(1) : 100
      
      # Get AI summary assessment
      assessment = get_daily_ai_assessment(executions)
      
      # Analyze patterns
      issues = analyze_daily_patterns(executions)
      improvements = generate_daily_improvements(executions, assessment)
      
      # Create reflection
      reflection = AgentReflection.create!(
        entity: @entity,
        agent_plugin: agent,
        reflection_type: 'daily',
        efficiency_score: assessment[:efficiency],
        quality_score: assessment[:quality],
        tool_usage_score: assessment[:tool_usage],
        communication_score: assessment[:communication],
        overall_score: calculate_overall_score(assessment),
        identified_issues: issues,
        improvement_ideas: improvements,
        knowledge_gaps: assessment[:knowledge_gaps] || [],
        strengths_identified: assessment[:strengths] || [],
        peer_comparison: compare_to_peers,
        learning_plan: generate_learning_plan(issues, improvements),
        raw_reflection: assessment[:raw_text]
      )
      
      reflection.update_overall_score!
      
      # Schedule learning if needed
      if reflection.has_learning_plan? && reflection.overall_score.to_i < 7
        schedule_learning_tasks(reflection)
      end
      
      reflection
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # WEEKLY REFLECTION
    # Comprehensive weekly review
    # ═══════════════════════════════════════════════════════════════════════════

    def weekly_reflection
      Rails.logger.info "[Metacognition] Agent #{agent.name} performing weekly reflection"
      
      executions = agent.agent_plugin_executions
        .where('created_at > ?', 7.days.ago)
      
      return nil if executions.count < 5
      
      # Get detailed analysis
      evolution_analysis = @evolution_service.analyze_agent(agent)
      
      # Weekly AI assessment
      assessment = get_weekly_ai_assessment(executions, evolution_analysis)
      
      # Trend analysis
      daily_reflections = AgentReflection.for_agent(agent)
        .by_type('daily')
        .where('created_at > ?', 7.days.ago)
        .order(:created_at)
      
      trend = calculate_score_trend(daily_reflections)
      
      # Create comprehensive reflection
      reflection = AgentReflection.create!(
        entity: @entity,
        agent_plugin: agent,
        reflection_type: 'weekly',
        efficiency_score: assessment[:efficiency],
        quality_score: assessment[:quality],
        tool_usage_score: assessment[:tool_usage],
        communication_score: assessment[:communication],
        overall_score: calculate_overall_score(assessment),
        identified_issues: evolution_analysis[:skill_gaps] + (assessment[:issues] || []),
        improvement_ideas: evolution_analysis[:recommended_training].map { |t| t.merge(actionable: true) },
        knowledge_gaps: assessment[:knowledge_gaps] || [],
        strengths_identified: assessment[:strengths] || [],
        skills_to_develop: evolution_analysis[:evolution_opportunities].map { |o| o[:type] },
        peer_comparison: compare_to_peers(detailed: true),
        learning_plan: generate_comprehensive_learning_plan(evolution_analysis),
        raw_reflection: assessment[:raw_text]
      )
      
      reflection.update_overall_score!
      
      # Record specializations discovered
      if assessment[:specializations].present?
        assessment[:specializations].each do |spec|
          AgentLifecycleEvent.record_specialization(agent, specialization: spec)
        end
        
        current_specs = agent.discovered_specializations || []
        agent.update!(discovered_specializations: (current_specs + assessment[:specializations]).uniq)
      end
      
      # Trigger training if needed
      if evolution_analysis[:evolution_score] < 70
        trigger_agent_school(reflection, evolution_analysis)
      end
      
      reflection
    end

    private

    # ═══════════════════════════════════════════════════════════════════════════
    # AI ASSESSMENT
    # ═══════════════════════════════════════════════════════════════════════════

    def get_ai_self_assessment(execution)
      prompt = build_execution_reflection_prompt(execution)
      
      begin
        response = BedrockService.new(entity: @entity).quick_completion(prompt)
        parse_assessment_response(response)
      rescue => e
        Rails.logger.error "[Metacognition] AI assessment failed: #{e.message}"
        default_assessment
      end
    end

    def get_daily_ai_assessment(executions)
      prompt = build_daily_reflection_prompt(executions)
      
      begin
        response = BedrockService.new(entity: @entity).quick_completion(prompt)
        parse_assessment_response(response)
      rescue => e
        Rails.logger.error "[Metacognition] Daily AI assessment failed: #{e.message}"
        default_assessment
      end
    end

    def get_weekly_ai_assessment(executions, evolution_analysis)
      prompt = build_weekly_reflection_prompt(executions, evolution_analysis)
      
      begin
        response = BedrockService.new(entity: @entity).quick_completion(prompt)
        parse_assessment_response(response, include_specializations: true)
      rescue => e
        Rails.logger.error "[Metacognition] Weekly AI assessment failed: #{e.message}"
        default_assessment
      end
    end

    def build_execution_reflection_prompt(execution)
      <<~PROMPT
        You are #{agent.name}, an AI agent. Reflect honestly on your performance in this task:
        
        Task: #{execution.input_context&.dig('task_description') || 'Unknown task'}
        Status: #{execution.status}
        Duration: #{execution.duration_ms}ms
        Tools Used: #{execution.output_result&.dig('tools_used')&.join(', ') || 'Unknown'}
        
        #{execution.status == 'failed' ? "Error: #{execution.output_result&.dig('error')}" : ''}
        
        Rate yourself honestly from 1-10 on:
        1. Efficiency: Did you complete the task quickly and with minimal steps?
        2. Quality: Was your output correct and high-quality?
        3. Tool Usage: Did you use the right tools effectively?
        4. Communication: Were you clear in your responses?
        
        Also identify:
        - What went well (strengths)
        - What could be improved
        - Any knowledge gaps you noticed
        
        Respond in JSON format:
        {
          "efficiency": 7,
          "quality": 8,
          "tool_usage": 6,
          "communication": 8,
          "strengths": ["clear communication", "fast completion"],
          "improvements": ["could use fewer API calls"],
          "knowledge_gaps": ["unfamiliar with X feature"],
          "reflection": "One paragraph honest reflection..."
        }
      PROMPT
    end

    def build_daily_reflection_prompt(executions)
      completed = executions.where(status: 'completed').count
      failed = executions.where(status: 'failed').count
      
      <<~PROMPT
        You are #{agent.name}, an AI agent. Reflect on your day's performance:
        
        Tasks Completed: #{completed}
        Tasks Failed: #{failed}
        Success Rate: #{completed + failed > 0 ? ((completed.to_f / (completed + failed)) * 100).round(1) : 100}%
        
        Common task types today:
        #{execution_type_summary(executions)}
        
        Reflect on your day and rate yourself 1-10 on efficiency, quality, tool_usage, communication.
        Identify patterns, what worked, what didn't, and areas for growth.
        
        Respond in JSON format with the same structure as individual reflection.
      PROMPT
    end

    def build_weekly_reflection_prompt(executions, evolution_analysis)
      <<~PROMPT
        You are #{agent.name}, an AI agent. Perform your weekly self-assessment:
        
        Week Summary:
        - Total Tasks: #{executions.count}
        - Success Rate: #{evolution_analysis.dig(:performance, :success_rate) || 'Unknown'}%
        - Evolution Score: #{evolution_analysis[:evolution_score]}
        
        Skill Gaps Identified:
        #{evolution_analysis[:skill_gaps].map { |g| "- #{g[:item]}: #{g[:recommendation]}" }.join("\n")}
        
        Training Recommendations:
        #{evolution_analysis[:recommended_training].map { |t| "- #{t[:type]}: #{t[:description]}" }.join("\n")}
        
        Perform a deep self-assessment. Rate yourself 1-10 on all dimensions.
        Identify your emerging specializations - what are you becoming really good at?
        What skills should you prioritize developing?
        
        Respond in JSON format including a "specializations" array of areas where you excel.
      PROMPT
    end

    def parse_assessment_response(response, include_specializations: false)
      begin
        json = JSON.parse(response)
        result = {
          efficiency: json['efficiency']&.to_i,
          quality: json['quality']&.to_i,
          tool_usage: json['tool_usage']&.to_i,
          communication: json['communication']&.to_i,
          strengths: json['strengths'] || [],
          improvements: json['improvements'] || [],
          knowledge_gaps: json['knowledge_gaps'] || [],
          raw_text: json['reflection'] || response
        }
        result[:specializations] = json['specializations'] if include_specializations
        result
      rescue JSON::ParserError
        default_assessment.merge(raw_text: response)
      end
    end

    def default_assessment
      {
        efficiency: 5,
        quality: 5,
        tool_usage: 5,
        communication: 5,
        strengths: [],
        improvements: [],
        knowledge_gaps: [],
        raw_text: 'Assessment could not be generated'
      }
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # ANALYSIS HELPERS
    # ═══════════════════════════════════════════════════════════════════════════

    def should_reflect?(execution)
      # Always reflect on failures
      return true if execution.status == 'failed'
      
      # Sample successful executions
      return true if rand < REFLECTION_SAMPLE_RATE
      
      # Reflect on long-running tasks
      return true if execution.duration_ms.to_i > 30_000
      
      false
    end

    def identify_issues(execution, assessment)
      issues = []
      
      if execution.status == 'failed'
        issues << {
          type: 'task_failure',
          severity: 'high',
          description: execution.output_result&.dig('error') || 'Task failed',
          actionable: true
        }
      end
      
      # Low scores are issues
      %i[efficiency quality tool_usage communication].each do |dimension|
        score = assessment[dimension].to_i
        if score <= 4
          issues << {
            type: "low_#{dimension}",
            severity: score <= 2 ? 'critical' : 'medium',
            description: "#{dimension.to_s.humanize} score is #{score}/10",
            actionable: true
          }
        end
      end
      
      issues
    end

    def generate_improvement_ideas(execution, assessment, issues)
      ideas = []
      
      assessment[:improvements]&.each do |improvement|
        ideas << {
          type: 'self_identified',
          description: improvement,
          actionable: true,
          source: 'self_reflection'
        }
      end
      
      issues.each do |issue|
        case issue[:type]
        when 'low_efficiency'
          ideas << { type: 'optimize_workflow', description: 'Reduce unnecessary steps', actionable: true }
        when 'low_tool_usage'
          ideas << { type: 'learn_tools', description: 'Practice using available tools', actionable: true }
        when 'task_failure'
          ideas << { type: 'error_handling', description: 'Improve error handling', actionable: true }
        end
      end
      
      ideas.uniq { |i| i[:description] }
    end

    def identify_knowledge_gaps(execution, assessment)
      gaps = assessment[:knowledge_gaps] || []
      
      # Add gaps from failed tool calls
      if execution.output_result&.dig('failed_tools').present?
        execution.output_result['failed_tools'].each do |tool|
          gaps << { topic: "Tool: #{tool}", source: 'failed_execution' }
        end
      end
      
      gaps.map do |gap|
        case gap
        when String
          { topic: gap, source: 'self_identified' }
        when Hash
          gap
        end
      end
    end

    def analyze_daily_patterns(executions)
      issues = []
      
      # Check for repeated failures
      failures = executions.where(status: 'failed')
      if failures.count > 3
        issues << {
          type: 'repeated_failures',
          severity: 'high',
          description: "#{failures.count} failed tasks today",
          actionable: true
        }
      end
      
      # Check for slow executions
      slow_count = executions.where('duration_ms > ?', 30_000).count
      if slow_count > executions.count * 0.3
        issues << {
          type: 'slow_performance',
          severity: 'medium',
          description: "#{(slow_count.to_f / executions.count * 100).round}% of tasks were slow",
          actionable: true
        }
      end
      
      issues
    end

    def generate_daily_improvements(executions, assessment)
      (assessment[:improvements] || []).map do |improvement|
        { type: 'daily_insight', description: improvement, actionable: true }
      end
    end

    def compare_to_peers(detailed: false)
      # Get similar agents
      peers = @entity.agent_plugins
        .where(status: 'active')
        .where.not(id: agent.id)
      
      return {} if peers.count < MIN_EXECUTIONS_FOR_COMPARISON
      
      # Get my stats
      my_executions = agent.agent_plugin_executions.where('created_at > ?', 7.days.ago)
      my_completed = my_executions.where(status: 'completed').count
      my_total = my_executions.count
      my_success_rate = my_total > 0 ? (my_completed.to_f / my_total) : 1.0
      
      # Get peer average
      peer_stats = peers.map do |peer|
        execs = peer.agent_plugin_executions.where('created_at > ?', 7.days.ago)
        completed = execs.where(status: 'completed').count
        total = execs.count
        total > 0 ? (completed.to_f / total) : 1.0
      end
      
      peer_avg = peer_stats.any? ? (peer_stats.sum / peer_stats.count) : 1.0
      
      comparison = {
        my_success_rate: (my_success_rate * 100).round(1),
        peer_average: (peer_avg * 100).round(1),
        relative_performance: my_success_rate >= peer_avg ? 'above_average' : 'below_average',
        percentile: calculate_percentile(my_success_rate, peer_stats)
      }
      
      if detailed
        comparison[:peer_count] = peers.count
        comparison[:rank] = peer_stats.count { |s| s < my_success_rate } + 1
      end
      
      comparison
    end

    def calculate_percentile(my_score, peer_scores)
      return 100 if peer_scores.empty?
      below_me = peer_scores.count { |s| s < my_score }
      ((below_me.to_f / peer_scores.count) * 100).round
    end

    def calculate_overall_score(assessment)
      scores = [
        assessment[:efficiency],
        assessment[:quality],
        assessment[:tool_usage],
        assessment[:communication]
      ].compact
      
      return nil if scores.empty?
      (scores.sum.to_f / scores.count).round
    end

    def calculate_score_trend(reflections)
      return 'unknown' if reflections.count < 3
      
      scores = reflections.filter_map(&:overall_score)
      return 'unknown' if scores.count < 3
      
      first_half = scores.first(scores.count / 2)
      second_half = scores.last(scores.count / 2)
      
      first_avg = first_half.sum.to_f / first_half.count
      second_avg = second_half.sum.to_f / second_half.count
      
      diff = second_avg - first_avg
      
      if diff > 0.5
        'improving'
      elsif diff < -0.5
        'declining'
      else
        'stable'
      end
    end

    def execution_type_summary(executions)
      types = executions.pluck(:input_context)
        .map { |c| c&.dig('task_type') || 'general' }
        .tally
        .sort_by { |_, count| -count }
        .first(5)
      
      types.map { |type, count| "- #{type}: #{count} tasks" }.join("\n")
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # LEARNING & TRAINING
    # ═══════════════════════════════════════════════════════════════════════════

    def generate_learning_plan(issues, improvements)
      return {} if issues.empty? && improvements.empty?
      
      modules = []
      
      issues.select { |i| i[:actionable] }.each do |issue|
        modules << {
          name: "Address: #{issue[:type]}",
          type: 'remediation',
          priority: issue[:severity] == 'critical' ? 'high' : 'medium',
          description: issue[:description]
        }
      end
      
      improvements.select { |i| i[:actionable] }.first(3).each do |improvement|
        modules << {
          name: "Improve: #{improvement[:description].truncate(30)}",
          type: 'improvement',
          priority: 'low',
          description: improvement[:description]
        }
      end
      
      { modules: modules, generated_at: Time.current }
    end

    def generate_comprehensive_learning_plan(evolution_analysis)
      modules = []
      
      # High priority: skill gaps
      evolution_analysis[:skill_gaps].each do |gap|
        modules << {
          name: "Close gap: #{gap[:item]}",
          type: gap[:type],
          priority: gap[:impact] == 'high' ? 'high' : 'medium',
          description: gap[:recommendation],
          estimated_duration: '1 hour'
        }
      end
      
      # Medium priority: training recommendations
      evolution_analysis[:recommended_training].each do |training|
        modules << {
          name: training[:type],
          type: 'training',
          priority: training[:priority],
          description: training[:description],
          focus_areas: training[:focus]
        }
      end
      
      { modules: modules, generated_at: Time.current }
    end

    def schedule_improvement_actions(reflection)
      # Create a goal for improvement
      AgentGoal.create!(
        entity: @entity,
        agent_plugin: agent,
        goal_type: 'improvement',
        title: "Improve based on reflection #{reflection.id}",
        description: "Agent self-identified issues that need addressing",
        priority: 70,
        source: 'agent_reflection',
        suggested_actions: reflection.improvement_ideas.map { |i| i[:type] },
        metadata: { reflection_id: reflection.id }
      )
    end

    def schedule_learning_tasks(reflection)
      reflection.learning_plan['modules']&.each do |mod|
        # Create scheduled task for each learning module
        ScheduledAgentTask.create!(
          entity: @entity,
          user: @entity.users.first,
          agent_plugin: agent,
          name: "Learning: #{mod['name']}",
          description: mod['description'],
          task_type: 'custom',
          prompt: build_learning_prompt(mod),
          schedule_type: 'once',
          next_run_at: 1.hour.from_now,
          enabled: true,
          execution_mode: 'agent_only'
        )
      end
      
      reflection.mark_learning_scheduled!
    end

    def build_learning_prompt(learning_module)
      <<~PROMPT
        Complete this learning module:
        
        Module: #{learning_module['name']}
        Type: #{learning_module['type']}
        Description: #{learning_module['description']}
        
        Instructions:
        1. Study the relevant documentation or examples
        2. Practice the skill or technique
        3. Add what you learned to your knowledge base
        4. Report your learning outcomes
      PROMPT
    end

    def trigger_agent_school(reflection, evolution_analysis)
      return if agent.in_school?
      
      goal = AgentGoal.create!(
        entity: @entity,
        agent_plugin: agent,
        goal_type: 'improvement',
        title: "Agent School enrollment for #{agent.name}",
        description: "Weekly reflection identified significant improvement opportunities",
        priority: 85,
        source: 'agent_reflection',
        metadata: {
          reflection_id: reflection.id,
          evolution_score: evolution_analysis[:evolution_score]
        }
      )
      
      reflection.update!(triggered_enrollment: goal.trigger_school_enrollment!)
    end
  end
end


