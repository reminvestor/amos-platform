# frozen_string_literal: true

# SkillEvolutionService - AMOS autonomously improves its own skills
#
# Unlike bounties (which need humans for code changes), skills are pure
# knowledge content that AMOS can update directly. This service:
#
# 1. Analyzes integration tool call success/failure patterns
# 2. Analyzes IntegrationSchemaLearner data for parameter patterns
# 3. Reviews skill injection logs for effectiveness
# 4. Uses an LLM call to generate improved skill content
# 5. Directly applies high-confidence improvements (no bounty needed)
#
# Runs as Phase 2.7 in the Evolution Cycle, and can also be triggered
# manually from the admin portal.
#
# Philosophy:
#   Skills = knowledge AMOS uses → AMOS can evolve these directly
#   Code = platform infrastructure → needs bounties for humans/agents
#
class SkillEvolutionService
  attr_reader :entity, :evolution_log

  # Minimum data points before we consider evolving a skill
  MIN_INJECTION_COUNT = 5
  MIN_TOOL_CALLS = 10

  # Only auto-apply changes if confidence is above this threshold
  AUTO_APPLY_CONFIDENCE = 0.7

  def initialize(entity)
    @entity = entity
    @evolution_log = []
  end

  # Main entry point: analyze all skills and evolve where data supports it
  # Returns: { skills_analyzed: N, skills_evolved: N, proposals: [...] }
  def evolve_skills!
    log("Starting skill evolution for #{entity.name}")

    skills = SystemSkill.active.global
    results = { skills_analyzed: 0, skills_evolved: 0, proposals: [] }

    skills.each do |skill|
      results[:skills_analyzed] += 1

      analysis = analyze_skill(skill)
      next unless analysis[:should_evolve]

      proposal = propose_evolution(skill, analysis)
      next unless proposal

      results[:proposals] << proposal

      if proposal[:confidence] >= AUTO_APPLY_CONFIDENCE
        apply_evolution!(skill, proposal)
        results[:skills_evolved] += 1
        log("✅ Auto-applied evolution to '#{skill.name}' (confidence: #{proposal[:confidence]})")
      else
        log("📋 Proposed evolution for '#{skill.name}' (confidence: #{proposal[:confidence]}) — needs review")
      end
    end

    log("Evolution complete: #{results[:skills_analyzed]} analyzed, #{results[:skills_evolved]} evolved, #{results[:proposals].count} proposals")
    results
  end

  # Analyze a single skill to determine if it should evolve
  def analyze_skill(skill)
    analysis = {
      skill_id: skill.id,
      skill_name: skill.name,
      should_evolve: false,
      signals: [],
      data_points: 0
    }

    # Signal 1: Integration tool call failures related to this skill
    if skill.integration_name.present?
      tool_analysis = analyze_integration_tool_calls(skill.integration_name)
      analysis[:tool_call_data] = tool_analysis
      analysis[:data_points] += tool_analysis[:total_calls]

      if tool_analysis[:failure_patterns].any?
        analysis[:signals] << {
          type: :tool_failures,
          strength: tool_analysis[:failure_rate],
          details: tool_analysis[:failure_patterns]
        }
      end

      if tool_analysis[:parameter_learnings].any?
        analysis[:signals] << {
          type: :parameter_learnings,
          strength: 0.6,
          details: tool_analysis[:parameter_learnings]
        }
      end
    end

    # Signal 2: Skill injection effectiveness
    if skill.injection_count >= MIN_INJECTION_COUNT
      effectiveness = skill.effectiveness_score
      if effectiveness.present? && effectiveness < 60
        analysis[:signals] << {
          type: :low_effectiveness,
          strength: (60 - effectiveness) / 60.0,
          details: { score: effectiveness, injections: skill.injection_count }
        }
      end
    end

    # Signal 3: Recent injection logs with poor outcomes
    recent_failures = skill.skill_injection_logs
                           .where('created_at > ?', 7.days.ago)
                           .where(outcome_positive: false)
                           .count
    recent_total = skill.skill_injection_logs
                        .where('created_at > ?', 7.days.ago)
                        .count

    if recent_total >= 3 && recent_failures.to_f / recent_total > 0.3
      analysis[:signals] << {
        type: :recent_failures,
        strength: recent_failures.to_f / recent_total,
        details: { failures: recent_failures, total: recent_total }
      }
    end

    # Determine if we should evolve
    analysis[:should_evolve] = analysis[:signals].any? && analysis[:data_points] >= MIN_TOOL_CALLS

    analysis
  end

  # Propose a specific evolution for a skill based on analysis
  def propose_evolution(skill, analysis)
    return nil if analysis[:signals].empty?

    # Build context for the LLM about what's going wrong
    failure_context = build_failure_context(skill, analysis)
    return nil if failure_context.blank?

    # Ask the LLM to improve the skill
    improved_content = generate_improved_skill(skill, failure_context)
    return nil if improved_content.blank? || improved_content == skill.content

    # Calculate confidence based on signal strength and data volume
    confidence = calculate_confidence(analysis)

    {
      skill_id: skill.id,
      skill_name: skill.name,
      current_content: skill.content,
      proposed_content: improved_content,
      confidence: confidence,
      reason: summarize_signals(analysis[:signals]),
      signals: analysis[:signals],
      data_points: analysis[:data_points]
    }
  end

  private

  # Analyze integration tool calls for failure patterns
  def analyze_integration_tool_calls(integration_name)
    result = {
      total_calls: 0,
      successful_calls: 0,
      failed_calls: 0,
      failure_rate: 0.0,
      failure_patterns: [],
      parameter_learnings: []
    }

    # Get recent tool executions for this integration
    recent_executions = AgentToolExecution
      .where(entity: entity)
      .where('created_at > ?', 30.days.ago)
      .where("tool_name ILIKE ?", "%#{integration_name}%")
      .or(
        AgentToolExecution
          .where(entity: entity)
          .where('created_at > ?', 30.days.ago)
          .where("tool_name = 'execute_integration_action'")
          .where("input_arguments->>'integration' = ?", integration_name)
      )
      .order(created_at: :desc)
      .limit(200)

    result[:total_calls] = recent_executions.count
    return result if result[:total_calls] == 0

    result[:successful_calls] = recent_executions.where(status: 'success').count
    result[:failed_calls] = recent_executions.where(status: 'error').count
    result[:failure_rate] = result[:failed_calls].to_f / result[:total_calls]

    # Extract failure patterns
    recent_executions.where(status: 'error').limit(20).each do |exec|
      error = exec.error_message || exec.output_result&.dig('error')
      next unless error.present?

      result[:failure_patterns] << {
        error: error.truncate(200),
        input: exec.input_arguments&.except('credentials', 'token', 'api_key'),
        tool: exec.tool_name
      }
    end

    # Deduplicate failure patterns by error message
    result[:failure_patterns] = result[:failure_patterns]
      .group_by { |p| p[:error] }
      .map { |error, patterns| { error: error, count: patterns.count, sample_input: patterns.first[:input] } }
      .sort_by { |p| -p[:count] }

    # Check IntegrationSchemaLearner for parameter learnings
    integration = Integration.find_by(slug: integration_name)
    if integration
      integration.integration_operations.each do |op|
        learnings = op.metadata&.dig('recent_failures') || []
        learnings.each do |learning|
          result[:parameter_learnings] << {
            operation: op.name,
            error: learning['error']&.truncate(150),
            params: learning['params']&.except('credentials', 'token')
          }
        end
      end
    end

    result
  rescue => e
    log("WARNING: Tool call analysis failed for #{integration_name}: #{e.message}")
    result
  end

  # Build context about failures for the LLM
  def build_failure_context(skill, analysis)
    parts = []

    analysis[:signals].each do |signal|
      case signal[:type]
      when :tool_failures
        parts << "## Tool Call Failures"
        signal[:details].each do |pattern|
          parts << "- Error (#{pattern[:count]}x): #{pattern[:error]}"
          parts << "  Sample input: #{pattern[:sample_input].to_json}" if pattern[:sample_input]
        end

      when :parameter_learnings
        parts << "\n## Parameter Learnings (from IntegrationSchemaLearner)"
        signal[:details].each do |learning|
          parts << "- Operation '#{learning[:operation]}': #{learning[:error]}"
        end

      when :low_effectiveness
        parts << "\n## Low Effectiveness Score"
        parts << "- Current score: #{signal[:details][:score]}% (after #{signal[:details][:injections]} injections)"
        parts << "- This means the skill content isn't helping users succeed"

      when :recent_failures
        parts << "\n## Recent Poor Outcomes"
        parts << "- #{signal[:details][:failures]}/#{signal[:details][:total]} recent injections had poor outcomes"
      end
    end

    parts.join("\n")
  end

  # Generate improved skill content using an LLM
  def generate_improved_skill(skill, failure_context)
    prompt = <<~PROMPT
      You are improving an AI skill file. Skills are expertise guides that get injected into
      an AI assistant's context to help it use APIs and tools correctly.

      CURRENT SKILL CONTENT:
      ```
      #{skill.content}
      ```

      OBSERVED PROBLEMS:
      #{failure_context}

      YOUR TASK:
      Improve the skill content to address the observed problems. Specifically:
      1. Add "DO NOT" entries for parameter mistakes that keep happening
      2. Add correct examples for operations that are failing
      3. Clarify any ambiguous instructions
      4. Add edge cases and gotchas that the failures reveal
      5. Keep everything that's already correct

      RULES:
      - Return ONLY the improved skill content (no explanations, no markdown fences)
      - Keep the same format and structure
      - Don't remove correct information
      - Be specific about what went wrong and what to do instead
      - Keep it concise — skills should be reference guides, not textbooks
    PROMPT

    response = call_llm(prompt)
    response&.strip
  rescue => e
    log("WARNING: LLM skill generation failed: #{e.message}")
    nil
  end

  # Apply an evolution directly to a skill
  def apply_evolution!(skill, proposal)
    skill.evolve!(
      proposal[:proposed_content],
      source: 'evolution',
      reason: proposal[:reason],
      details: {
        confidence: proposal[:confidence],
        signals: proposal[:signals].map { |s| s.slice(:type, :strength) },
        data_points: proposal[:data_points]
      }
    )
  end

  # Calculate confidence in the proposed change
  def calculate_confidence(analysis)
    base = 0.3

    # More data = more confidence
    data_factor = [analysis[:data_points] / 100.0, 0.3].min
    base += data_factor

    # Stronger signals = more confidence
    if analysis[:signals].any?
      avg_strength = analysis[:signals].sum { |s| s[:strength] } / analysis[:signals].count
      base += avg_strength * 0.3
    end

    # Multiple signal types = more confidence
    signal_types = analysis[:signals].map { |s| s[:type] }.uniq.count
    base += signal_types * 0.05

    base.clamp(0.0, 1.0).round(2)
  end

  def summarize_signals(signals)
    parts = signals.map do |signal|
      case signal[:type]
      when :tool_failures then "tool call failures detected"
      when :parameter_learnings then "parameter patterns learned"
      when :low_effectiveness then "low effectiveness score"
      when :recent_failures then "recent poor outcomes"
      else signal[:type].to_s
      end
    end
    "Auto-evolved: #{parts.join(', ')}"
  end

  def call_llm(prompt)
    if defined?(BedrockService)
      service = BedrockService.new(entity: entity)
      service.quick_completion(prompt)
    elsif defined?(LlmService)
      LlmService.chat(system: "You are a skill file editor.", user: prompt, temperature: 0.3)
    else
      raise "No LLM service available"
    end
  end

  def log(message)
    @evolution_log << "[#{Time.current.strftime('%H:%M:%S')}] #{message}"
    Rails.logger.info "[SkillEvolution] #{message}"
  end
end
