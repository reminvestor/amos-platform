# frozen_string_literal: true

module Agents
  # Smart routing service that uses historical data to find the best agent for a task
  # Considers: success rates, tool matches, confidence scores, and current workload
  class SmartRouterService
    attr_reader :entity, :user

    def initialize(entity:, user: nil)
      @entity = entity
      @user = user
    end

    # Find the best agent for a given task
    # Returns ranked list of agents with scores
    def find_best_agent(task_description:, task_type: nil, tools_needed: [], object_types: [], top_n: 5, 
                        prefer_cost_efficient: false, balance_workload: true)
      candidates = gather_candidates(task_type: task_type, tools_needed: tools_needed)
      
      return [] if candidates.empty?

      scored = candidates.map do |agent|
        score_agent(agent, 
          task_description: task_description,
          task_type: task_type,
          tools_needed: tools_needed,
          object_types: object_types,
          prefer_cost_efficient: prefer_cost_efficient,
          balance_workload: balance_workload
        )
      end

      scored.sort_by { |s| -s[:total_score] }.first(top_n)
    end

    # Auto-select the single best agent (or nil if none qualify)
    def auto_select(task_description:, task_type: nil, tools_needed: [], min_score: 50)
      results = find_best_agent(
        task_description: task_description,
        task_type: task_type,
        tools_needed: tools_needed
      )

      best = results.first
      return nil unless best && best[:total_score] >= min_score

      best[:agent]
    end

    # Analyze routing patterns and identify improvements
    def routing_analysis
      recent_proposals = AgentTaskProposal.where(entity: entity)
        .where('created_at > ?', 30.days.ago)

      {
        total_proposals: recent_proposals.count,
        acceptance_rate: calculate_rate(recent_proposals, :accepted),
        success_rate: calculate_rate(recent_proposals.where(status: %w[completed failed]), :task_succeeded),
        top_rejection_reasons: top_rejection_reasons(recent_proposals),
        busiest_agents: busiest_agents(recent_proposals),
        capability_gaps: aggregate_capability_gaps(recent_proposals),
        recommendations: generate_recommendations(recent_proposals)
      }
    end

    private

    def gather_candidates(task_type:, tools_needed:)
      # Start with all active agents
      agents = AgentPlugin.where(status: 'active')
        .where('entity_id = ? OR entity_id IS NULL', entity.id)

      # If task type specified, prefer agents with history for that type
      if task_type.present?
        agents_with_history = AgentTaskProposal
          .where(entity: entity, task_type: task_type, task_succeeded: true)
          .distinct
          .pluck(:receiving_agent_id)

        # Boost agents with successful history (but don't exclude others)
        agents = agents.order(
          Arel.sql("CASE WHEN id IN (#{agents_with_history.join(',').presence || '0'}) THEN 0 ELSE 1 END")
        )
      end

      agents.limit(20).to_a
    end

    def score_agent(agent, task_description:, task_type:, tools_needed:, object_types:, 
                    prefer_cost_efficient: false, balance_workload: true)
      scores = {
        agent: agent,
        agent_slug: agent.slug,
        agent_name: agent.name,
        breakdown: {}
      }

      # 1. Tool Match Score (0-30 points)
      agent_tools = agent.agent_tools.pluck(:tool_name)
      if tools_needed.present?
        matched = (agent_tools & tools_needed).length
        tool_score = (matched.to_f / tools_needed.length) * 30
        scores[:breakdown][:tools] = {
          score: tool_score.round(1),
          matched: matched,
          needed: tools_needed.length,
          available: agent_tools
        }
      else
        scores[:breakdown][:tools] = { score: 15, note: 'No specific tools required' }
      end

      # 2. Historical Success Score (0-30 points)
      # In development, use neutral scoring to avoid polluted test data affecting routing
      # In production, use actual historical performance
      if Rails.env.development?
        # Development: neutral history score - let domain matching decide
        scores[:breakdown][:history] = {
          score: 15,
          success_rate: 50.0,
          sample_size: 0,
          confidence: 0,
          source: 'dev_neutral'
        }
      else
        # Production: use actual historical performance
        # Only count COMPLETED tasks (completed/failed), not pending/accepted/executing
        base_proposals = AgentTaskProposal.where(receiving_agent: agent)
          .where(status: %w[completed failed])
        
        # Try task_type specific first, then fallback to all completed
        if task_type.present?
          typed_proposals = base_proposals.where(task_type: task_type)
          if typed_proposals.exists?
            completed_proposals = typed_proposals
            history_source = 'task_type'
          else
            completed_proposals = base_proposals
            history_source = 'overall'
          end
        else
          completed_proposals = base_proposals
          history_source = 'overall'
        end
        
        completed_count = completed_proposals.count
        successful_count = completed_proposals.where(task_succeeded: true).count
        
        if completed_count > 0
          success_rate = successful_count.to_f / completed_count
          confidence_multiplier = [completed_count / 10.0, 1.0].min
          history_score = success_rate * 30 * confidence_multiplier
        else
          # No history - give neutral score, don't penalize new agents
          success_rate = 0.5
          history_score = 10
          confidence_multiplier = 0
        end
        
        scores[:breakdown][:history] = {
          score: history_score.round(1),
          success_rate: (success_rate * 100).round(1),
          sample_size: completed_count,
          confidence: (confidence_multiplier * 100).round,
          source: history_source
        }
      end

      # 3. Role Match Score (0-20 points)
      role_score = calculate_role_match(agent, task_type, task_description)
      scores[:breakdown][:role] = role_score
      
      # 3b. Domain/Name Match Score (0-25 points) - STRONG signal from agent name/description
      domain_score = calculate_domain_match(agent, task_description)
      scores[:breakdown][:domain] = domain_score

      # 4. Current Workload Score (0-10 points) - Favor less busy agents
      active_tasks = AgentTaskProposal.where(
        receiving_agent: agent,
        status: 'executing'
      ).count
      
      if balance_workload
        # Penalize busy agents more heavily
        workload_score = case active_tasks
          when 0 then 10
          when 1 then 8
          when 2 then 5
          when 3 then 2
          else 0
        end
      else
        workload_score = 5 # Neutral if workload balancing disabled
      end
      
      scores[:breakdown][:workload] = {
        score: workload_score,
        active_tasks: active_tasks,
        balancing_enabled: balance_workload
      }

      # 5. Capability Match Score (0-10 points)
      capabilities = agent.capabilities_definition&.dig('capabilities') || []
      capability_score = capabilities.any? ? 10 : 5
      scores[:breakdown][:capabilities] = {
        score: capability_score,
        capabilities: capabilities
      }

      # 6. Cost Efficiency Score (0-10 points) - For simple tasks, prefer lighter models
      cost_score = calculate_cost_score(agent, task_description, prefer_cost_efficient)
      scores[:breakdown][:cost] = cost_score

      # Calculate total
      scores[:total_score] = scores[:breakdown].values.sum { |v| v.is_a?(Hash) ? (v[:score] || 0) : 0 }
      scores[:confidence] = calculate_confidence(scores)
      scores[:recommendation] = build_recommendation(scores)

      scores
    end

    def calculate_cost_score(agent, task_description, prefer_cost_efficient)
      # Model cost tiers (lower is cheaper)
      model_costs = {
        'claude-3-5-haiku' => 1,
        'claude-3-haiku' => 1,
        'gpt-4o-mini' => 1,
        'claude-3-5-sonnet' => 3,
        'claude-sonnet-4-20250514' => 3,
        'gpt-4o' => 3,
        'gpt-4' => 4,
        'claude-opus-4-20250514' => 5,
        'claude-3-opus' => 5,
        'o1' => 5
      }

      agent_model = agent.configuration&.dig('model') || 'qwen3-next-80b'
      model_tier = model_costs[agent_model] || 3

      # Estimate task complexity from description
      task_complexity = estimate_task_complexity(task_description)

      if prefer_cost_efficient
        # Strongly favor cheaper models
        if task_complexity == 'simple' && model_tier <= 2
          { score: 10, model: agent_model, tier: model_tier, complexity: task_complexity }
        elsif task_complexity == 'simple' && model_tier >= 4
          { score: 2, model: agent_model, tier: model_tier, complexity: task_complexity, 
            note: 'Expensive model for simple task' }
        elsif model_tier <= 3
          { score: 7, model: agent_model, tier: model_tier, complexity: task_complexity }
        else
          { score: 4, model: agent_model, tier: model_tier, complexity: task_complexity }
        end
      else
        # Neutral - prefer matching complexity to model tier
        if task_complexity == 'complex' && model_tier >= 4
          { score: 8, model: agent_model, tier: model_tier, complexity: task_complexity }
        elsif task_complexity == 'simple' && model_tier <= 2
          { score: 8, model: agent_model, tier: model_tier, complexity: task_complexity }
        else
          { score: 5, model: agent_model, tier: model_tier, complexity: task_complexity }
        end
      end
    end

    def estimate_task_complexity(description)
      return 'medium' if description.blank?

      desc_lower = description.downcase

      # Complex indicators
      complex_keywords = %w[
        analyze design architect build create implement 
        integrate migrate transform complex multiple
        research deep-dive comprehensive
      ]

      # Simple indicators
      simple_keywords = %w[
        update get list show view check status
        find lookup query simple quick
      ]

      complex_count = complex_keywords.count { |k| desc_lower.include?(k) }
      simple_count = simple_keywords.count { |k| desc_lower.include?(k) }

      if complex_count >= 2 || desc_lower.length > 200
        'complex'
      elsif simple_count >= 2 || desc_lower.length < 50
        'simple'
      else
        'medium'
      end
    end

    def calculate_role_match(agent, task_type, task_description)
      role = agent.role.to_s.downcase
      score = 10 # Base score

      # Match role to task type
      role_task_matches = {
        'architect' => %w[fix_module update_schema add_field create_tool],
        'engineer' => %w[create_tool update_tool fix_canvas],
        'analyst' => %w[analyze query_data research],
        'assistant' => %w[create_record update_record custom],
        'fixer' => %w[fix_module fix_canvas update_schema]
      }

      if task_type && role_task_matches[role]&.include?(task_type)
        score += 10
      end

      # Bonus for description keywords matching role
      description_lower = task_description.to_s.downcase
      if role == 'architect' && description_lower.match?(/design|schema|module|field/)
        score += 5
      elsif role == 'engineer' && description_lower.match?(/build|create|tool|code/)
        score += 5
      elsif role == 'analyst' && description_lower.match?(/analyze|report|metric|data/)
        score += 5
      end

      { score: [score, 20].min, role: role }
    end
    
    # Calculate domain match based on agent name/description matching task description
    # This is a STRONG signal - if user says "landing page" and agent is "Landing Page Manager",
    # that should be a strong match
    def calculate_domain_match(agent, task_description)
      return { score: 0, matches: [] } if task_description.blank?
      
      task_lower = task_description.downcase
      agent_name_lower = agent.name.to_s.downcase
      agent_desc_lower = agent.description.to_s.downcase
      agent_slug_lower = agent.slug.to_s.downcase
      
      matches = []
      score = 0
      
      # Extract key domain terms from task description
      domain_terms = extract_domain_terms(task_lower)
      
      domain_terms.each do |term|
        # Strong match: term appears in agent name or slug - this is a VERY strong signal
        if agent_name_lower.include?(term) || agent_slug_lower.include?(term.gsub(' ', '_'))
          matches << { term: term, location: 'name', weight: 'strong' }
          score += 20  # Increased from 12 - name match is very significant
        # Moderate match: term appears in agent description
        elsif agent_desc_lower.include?(term)
          matches << { term: term, location: 'description', weight: 'moderate' }
          score += 8
        end
      end
      
      # Cap at 35 points (domain match can be the deciding factor)
      { score: [score, 35].min, matches: matches }
    end
    
    # Extract domain-specific terms from task description
    def extract_domain_terms(task)
      # Common domain keywords that map to agent specializations
      domain_keywords = [
        'landing page', 'landing-page', 'landingpage',
        'email', 'campaign', 'newsletter',
        'integration', 'api', 'connect', 'sync',
        'analytics', 'report', 'dashboard', 'metrics',
        'module', 'schema', 'database', 'field',
        'tool', 'workflow', 'automation',
        'research', 'search', 'investigate',
        'agent', 'assistant', 'bot',
        'image', 'photo', 'design', 'visual',
        'document', 'export', 'pdf', 'csv',
        'contact', 'lead', 'customer', 'crm',
        'social media', 'instagram', 'twitter', 'linkedin',
        'weather', 'forecast',
        'investment', 'investor', 'pitch deck',
        'swot', 'roi', 'analysis'
      ]
      
      found = []
      domain_keywords.each do |keyword|
        found << keyword if task.include?(keyword)
      end
      
      found
    end

    def calculate_confidence(scores)
      total = scores[:total_score]
      
      if total >= 80
        'high'
      elsif total >= 60
        'medium'
      elsif total >= 40
        'low'
      else
        'very_low'
      end
    end

    def build_recommendation(scores)
      total = scores[:total_score]
      breakdown = scores[:breakdown]

      if total >= 80
        "Excellent match - #{scores[:agent_name]} is highly qualified"
      elsif total >= 60
        issues = []
        issues << "limited history" if breakdown[:history][:sample_size] < 5
        issues << "missing some tools" if breakdown[:tools][:matched].to_i < breakdown[:tools][:needed].to_i
        "Good match#{issues.any? ? " (#{issues.join(', ')})" : ''}"
      elsif total >= 40
        "Acceptable but not ideal - consider alternatives"
      else
        "Not recommended - significant capability gaps"
      end
    end

    def calculate_rate(scope, field)
      return 0.0 if scope.count.zero?
      scope.where(field => true).count.to_f / scope.count
    end

    def top_rejection_reasons(proposals)
      proposals.where(status: 'rejected')
        .pluck(:rejection_reason)
        .compact
        .tally
        .sort_by { |_, v| -v }
        .first(5)
        .to_h
    end

    def busiest_agents(proposals)
      proposals.where(status: 'executing')
        .joins(:receiving_agent)
        .group('agent_plugins.slug', 'agent_plugins.name')
        .count
        .sort_by { |_, v| -v }
        .first(5)
        .map { |(slug, name), count| { slug: slug, name: name, active_tasks: count } }
    end

    def aggregate_capability_gaps(proposals)
      rejected = proposals.where(status: 'rejected')
      
      {
        missing_tools: rejected.pluck(:missing_tools).flatten.compact.tally.sort_by { |_, v| -v }.first(10).to_h,
        missing_capabilities: rejected.pluck(:missing_capabilities).flatten.compact.tally.sort_by { |_, v| -v }.first(10).to_h
      }
    end

    def generate_recommendations(proposals)
      gaps = aggregate_capability_gaps(proposals)
      recs = []

      # Recommend creating frequently missing tools
      gaps[:missing_tools].each do |tool, count|
        next if count < 3
        recs << {
          type: 'create_tool',
          priority: count >= 10 ? 'high' : 'medium',
          suggestion: "Create tool '#{tool}' - missing in #{count} proposals",
          tool_name: tool
        }
      end

      # Recommend training agents on missing capabilities
      gaps[:missing_capabilities].each do |cap, count|
        next if count < 3
        recs << {
          type: 'train_agent',
          priority: count >= 10 ? 'high' : 'medium',
          suggestion: "Train agents on '#{cap}' capability - gap in #{count} proposals",
          capability: cap
        }
      end

      recs.sort_by { |r| r[:priority] == 'high' ? 0 : 1 }
    end
  end
end

