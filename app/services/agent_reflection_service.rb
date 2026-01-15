# frozen_string_literal: true

# AgentReflectionService
#
# Handles the continuous learning and self-improvement cycle for agents.
# Agents should periodically reflect on their performance, analyze feedback,
# search for new knowledge, and leave notes for their future selves.
#
# This runs as a scheduled task for each agent, typically weekly or daily.
#
# Reflection Phases:
# 1. TASK_ANALYSIS: Review recent task executions and outcomes
# 2. FEEDBACK_ANALYSIS: Analyze user feedback and ratings
# 3. GAP_IDENTIFICATION: Identify knowledge gaps from failures
# 4. KNOWLEDGE_ACQUISITION: Research to fill identified gaps
# 5. SELF_NOTES: Generate notes and insights for future reference
#
# Usage:
#   service = AgentReflectionService.new(agent)
#   service.run_reflection_cycle!
#
class AgentReflectionService
  REFLECTION_PHASES = %w[task_analysis feedback_analysis api_call_analysis gap_identification knowledge_acquisition self_notes].freeze
  
  # Minimum time between reflections (prevent too frequent runs)
  MIN_REFLECTION_INTERVAL = 6.hours
  
  attr_reader :agent, :reflection_log, :insights

  def initialize(agent)
    @agent = agent
    @reflection_log = []
    @insights = {
      tasks_analyzed: 0,
      feedback_analyzed: 0,
      gaps_identified: [],
      knowledge_added: 0,
      notes_created: 0
    }
  end

  # Run the full reflection cycle
  def run_reflection_cycle!
    return skip_if_too_recent if reflected_recently?
    
    log_event("🔄 Starting reflection cycle for agent: #{agent.name}")
    
    REFLECTION_PHASES.each do |phase|
      log_event("📚 Phase: #{phase}")
      
      begin
        send("#{phase}_phase!")
      rescue => e
        log_event("⚠️ Phase #{phase} failed: #{e.message}")
      end
    end
    
    # Update agent's last reflection timestamp
    update_reflection_metadata
    
    log_event("✅ Reflection cycle complete")
    
    {
      success: true,
      insights: @insights,
      log: @reflection_log
    }
  end

  # Phase 1: Analyze recent task executions
  def task_analysis_phase!
    # Get recent executions for this agent
    executions = agent.agent_plugin_executions
                      .where('created_at > ?', last_reflection_time)
                      .order(created_at: :desc)
                      .limit(50)
    
    return log_event("  No new executions to analyze") if executions.empty?
    
    # Categorize by outcome
    successful = executions.where(status: 'completed').count
    failed = executions.where(status: 'failed').count
    total = executions.count
    
    @insights[:tasks_analyzed] = total
    success_rate = total > 0 ? (successful.to_f / total * 100).round(1) : 0
    
    log_event("  Analyzed #{total} tasks: #{successful} success, #{failed} failed (#{success_rate}% success rate)")
    
    # Analyze failure patterns
    failed_executions = executions.where(status: 'failed')
    if failed_executions.any?
      failure_reasons = analyze_failure_patterns(failed_executions)
      @insights[:failure_patterns] = failure_reasons
      
      failure_reasons.each do |reason, count|
        log_event("  ⚠️ Failure pattern: #{reason} (#{count}x)")
        @insights[:gaps_identified] << reason
      end
    end
  end

  # Phase 2: Analyze user feedback
  def feedback_analysis_phase!
    # Get recent feedback for this agent's executions
    feedbacks = UserFeedback.joins(:agent_plugin_execution)
                            .where(agent_plugin_executions: { agent_plugin_id: agent.id })
                            .where('user_feedbacks.created_at > ?', last_reflection_time)
                            .limit(50)
    
    return log_event("  No new feedback to analyze") if feedbacks.empty?
    
    @insights[:feedback_analyzed] = feedbacks.count
    
    # Analyze ratings
    avg_rating = feedbacks.where.not(rating: nil).average(:rating)&.round(2)
    log_event("  Analyzed #{feedbacks.count} feedbacks, avg rating: #{avg_rating || 'N/A'}")
    
    # Extract improvement suggestions from negative feedback
    negative_feedbacks = feedbacks.where('rating < ?', 3).where.not(comment: nil)
    
    negative_feedbacks.each do |feedback|
      insight = extract_feedback_insight(feedback)
      if insight
        @insights[:gaps_identified] << insight
        log_event("  💡 Insight from feedback: #{insight.truncate(50)}")
      end
    end
  end

  # Phase 3: Analyze API call patterns (for integration agents)
  def api_call_analysis_phase!
    domain_config = detect_domain_config
    return log_event("  Not an integration agent, skipping API analysis") unless domain_config
    
    integration_name = domain_config[:integration]
    integration = Integration.find_by(slug: integration_name)
    return log_event("  Integration not found: #{integration_name}") unless integration
    
    log_event("  📊 Analyzing API call patterns for #{integration_name}")
    
    # Find recent successful and failed API calls
    analyze_recent_api_calls(integration)
    
    # Learn from new operations that were added
    learn_from_new_operations(integration)
  end

  # Phase 4: Identify knowledge gaps from analysis
  def gap_identification_phase!
    gaps = @insights[:gaps_identified].uniq
    
    return log_event("  No knowledge gaps identified") if gaps.empty?
    
    log_event("  Identified #{gaps.size} potential knowledge gaps:")
    
    # Prioritize gaps by frequency/importance
    gap_queries = gaps.map do |gap|
      {
        gap: gap,
        search_query: generate_search_query(gap),
        priority: calculate_gap_priority(gap)
      }
    end.sort_by { |g| -g[:priority] }
    
    @insights[:prioritized_gaps] = gap_queries.first(5) # Top 5 gaps
    
    gap_queries.first(5).each do |g|
      log_event("    - #{g[:gap]} (priority: #{g[:priority]})")
    end
  end

  # Phase 4: Research and acquire new knowledge
  def knowledge_acquisition_phase!
    gaps = @insights[:prioritized_gaps] || []
    
    return log_event("  No gaps to research") if gaps.empty?
    
    gaps.each do |gap_info|
      query = gap_info[:search_query]
      log_event("  🔍 Researching: #{query.truncate(50)}")
      
      begin
        # Perform web search
        results = perform_web_search(query)
        
        if results.any?
          # Add to agent's knowledge base
          content = format_research_for_knowledge(gap_info[:gap], results)
          
          agent.add_to_knowledge(
            content: content,
            title: "Reflection Research: #{gap_info[:gap].truncate(50)}",
            source: 'reflection_research',
            metadata: {
              phase: 'reflection',
              gap: gap_info[:gap],
              researched_at: Time.current.iso8601
            }
          )
          
          @insights[:knowledge_added] += 1
          log_event("    ✅ Added research to knowledge base")
        else
          log_event("    ⚠️ No research results found")
        end
      rescue => e
        log_event("    ❌ Research failed: #{e.message}")
      end
    end
  end

  # Phase 5: Generate self-notes for future reference
  def self_notes_phase!
    notes = []
    
    # Generate performance note
    if @insights[:tasks_analyzed] > 0
      success_rate = calculate_success_rate
      performance_trend = compare_to_previous_period
      
      notes << {
        type: 'performance',
        content: generate_performance_note(success_rate, performance_trend)
      }
    end
    
    # Generate learning note from gaps
    if @insights[:gaps_identified].any?
      notes << {
        type: 'learning',
        content: generate_learning_note(@insights[:gaps_identified])
      }
    end
    
    # Generate goal note for next period
    notes << {
      type: 'goal',
      content: generate_goal_note
    }
    
    # Save notes to agent's knowledge base
    notes.each do |note|
      agent.add_to_knowledge(
        content: note[:content],
        title: "Self-Note (#{note[:type]}): #{Time.current.strftime('%Y-%m-%d')}",
        source: 'self_reflection',
        metadata: {
          phase: 'self_notes',
          note_type: note[:type],
          reflection_date: Time.current.iso8601
        }
      )
      
      @insights[:notes_created] += 1
      log_event("  📝 Created #{note[:type]} note")
    end
  end

  private

  def last_reflection_time
    last_reflection = agent.metadata&.dig('last_reflection_at')
    last_reflection ? Time.parse(last_reflection) : 30.days.ago
  end

  def reflected_recently?
    last = agent.metadata&.dig('last_reflection_at')
    return false unless last
    
    Time.parse(last) > MIN_REFLECTION_INTERVAL.ago
  end

  def skip_if_too_recent
    log_event("⏭️ Skipping reflection - ran too recently")
    { success: false, reason: 'too_recent' }
  end

  def update_reflection_metadata
    agent.update!(
      metadata: agent.metadata.merge(
        'last_reflection_at' => Time.current.iso8601,
        'reflection_count' => (agent.metadata&.dig('reflection_count') || 0) + 1,
        'last_reflection_insights' => @insights
      )
    )
  end

  def analyze_failure_patterns(failed_executions)
    patterns = Hash.new(0)
    
    failed_executions.each do |execution|
      error = execution.error_message || execution.metadata&.dig('error') || 'unknown'
      
      # Categorize the error
      category = categorize_error(error)
      patterns[category] += 1
    end
    
    patterns.sort_by { |_, count| -count }.first(5).to_h
  end

  def categorize_error(error)
    error_str = error.to_s.downcase
    
    case error_str
    when /api|request|response|timeout|connection/
      'API/Integration Issues'
    when /permission|unauthorized|forbidden/
      'Permission/Authorization'
    when /not found|missing|nil/
      'Missing Data/Resources'
    when /syntax|parse|json|format/
      'Data Format/Syntax Issues'
    when /validation|invalid|required/
      'Validation Errors'
    when /limit|quota|rate/
      'Rate Limiting'
    else
      'Other/Unknown'
    end
  end

  def extract_feedback_insight(feedback)
    return nil if feedback.comment.blank?
    
    comment = feedback.comment.to_s.strip
    return nil if comment.length < 10
    
    # Extract actionable insight
    # Could use AI here for better extraction
    if comment.match?(/should|could|need|missing|wrong|incorrect|better/i)
      comment.truncate(200)
    else
      nil
    end
  end

  def generate_search_query(gap)
    domain_config = detect_domain_config
    integration = domain_config&.dig(:integration) || 'general'
    
    "#{integration} API #{gap} best practices"
  end

  def calculate_gap_priority(gap)
    # Higher priority for more frequent/impactful gaps
    base_priority = 1
    
    # Boost for integration-related gaps
    base_priority += 2 if gap.match?(/api|integration|query|parameter/i)
    
    # Boost for error-related gaps
    base_priority += 3 if gap.match?(/error|fail|issue|problem/i)
    
    base_priority
  end

  def perform_web_search(query)
    return [] unless defined?(Tools::WebSearchTool)
    
    tool = Tools::WebSearchTool.new(
      user: agent.user,
      entity: agent.entity,
      context: {}
    )
    
    result = tool.execute({
      'query' => query,
      'num_results' => 3
    })
    
    result[:results] || result['results'] || []
  rescue => e
    Rails.logger.warn "[AgentReflection] Web search failed: #{e.message}"
    []
  end

  def format_research_for_knowledge(gap, results)
    content = "# Research: #{gap}\n\n"
    content += "Researched during reflection on: #{Time.current.strftime('%Y-%m-%d')}\n\n"
    
    results.each_with_index do |result, i|
      title = result['title'] || result[:title] || 'Untitled'
      url = result['url'] || result[:url]
      snippet = result['snippet'] || result[:snippet] || ''
      
      content += "## Source #{i + 1}: #{title}\n"
      content += "URL: #{url}\n" if url
      content += "#{snippet}\n\n"
    end
    
    content
  end

  # Analyze recent API calls for patterns and learnings
  def analyze_recent_api_calls(integration)
    connections = IntegrationConnection.where(integration: integration)
    return if connections.empty?
    
    successful_patterns = []
    failure_patterns = []
    
    connections.each do |conn|
      next unless conn.respond_to?(:api_call_logs)
      
      # Get recent calls since last reflection
      recent_calls = conn.api_call_logs.where('created_at > ?', last_reflection_time)
      
      recent_calls.each do |call|
        if call.status == 'success'
          successful_patterns << {
            operation: call.operation_id,
            params: call.request_params
          }
        else
          failure_patterns << {
            operation: call.operation_id,
            params: call.request_params,
            error: call.error_message
          }
          @insights[:gaps_identified] << "API error in #{call.operation_id}: #{call.error_message.to_s.truncate(50)}"
        end
      end
    end
    
    # Learn from successful patterns
    if successful_patterns.any?
      content = "# Successful API Call Patterns (Reflection)\n\n"
      content += "Analyzed: #{Time.current.strftime('%Y-%m-%d')}\n\n"
      
      successful_patterns.group_by { |p| p[:operation] }.each do |op, patterns|
        content += "## #{op}\n"
        content += "Successful calls: #{patterns.size}\n\n"
        
        # Show example params
        if patterns.first[:params].present?
          content += "Example params:\n```json\n#{JSON.pretty_generate(patterns.first[:params])}\n```\n\n"
        end
      end
      
      agent.add_to_knowledge(
        content: content,
        title: "Successful Patterns: #{integration.name} (#{Time.current.strftime('%Y-%m-%d')})",
        source: 'reflection_api_analysis',
        metadata: { phase: 'reflection', type: 'successful_patterns' }
      )
      
      @insights[:knowledge_added] += 1
      log_event("    ✅ Learned from #{successful_patterns.size} successful API calls")
    end
    
    # Note failures for gap identification
    if failure_patterns.any?
      log_event("    ⚠️ Found #{failure_patterns.size} failed API calls to learn from")
    end
  rescue => e
    log_event("    ⚠️ API call analysis failed: #{e.message}")
  end

  # Check for new operations added since last reflection
  def learn_from_new_operations(integration)
    new_ops = integration.integration_operations
                         .where('created_at > ?', last_reflection_time)
    
    return if new_ops.empty?
    
    content = "# New Operations Available\n\n"
    content += "Discovered: #{Time.current.strftime('%Y-%m-%d')}\n\n"
    
    new_ops.each do |op|
      content += "## #{op.name} (#{op.operation_id})\n"
      content += "- Method: #{op.http_method}\n"
      content += "- Path: #{op.path_template}\n"
      content += "- Description: #{op.description}\n\n"
    end
    
    agent.add_to_knowledge(
      content: content,
      title: "New Operations: #{integration.name}",
      source: 'reflection_new_ops',
      metadata: { phase: 'reflection', type: 'new_operations' }
    )
    
    @insights[:knowledge_added] += 1
    log_event("    📄 Learned #{new_ops.count} new operations")
  rescue => e
    log_event("    ⚠️ New operation check failed: #{e.message}")
  end

  def calculate_success_rate
    executions = agent.agent_plugin_executions
                      .where('created_at > ?', last_reflection_time)
    
    return 0 if executions.empty?
    
    successful = executions.where(status: 'completed').count
    (successful.to_f / executions.count * 100).round(1)
  end

  def compare_to_previous_period
    current_period = agent.agent_plugin_executions
                          .where('created_at > ?', last_reflection_time)
    
    previous_start = 2 * (Time.current - last_reflection_time).seconds.ago
    previous_end = last_reflection_time
    
    previous_period = agent.agent_plugin_executions
                           .where('created_at > ? AND created_at <= ?', previous_start, previous_end)
    
    return 'no_comparison' if previous_period.empty?
    
    current_rate = current_period.any? ? 
      (current_period.where(status: 'completed').count.to_f / current_period.count * 100) : 0
    
    previous_rate = previous_period.any? ?
      (previous_period.where(status: 'completed').count.to_f / previous_period.count * 100) : 0
    
    diff = current_rate - previous_rate
    
    if diff > 5
      'improving'
    elsif diff < -5
      'declining'
    else
      'stable'
    end
  end

  def generate_performance_note(success_rate, trend)
    <<~NOTE
      # Performance Reflection - #{Time.current.strftime('%Y-%m-%d')}
      
      ## Summary
      - Success Rate: #{success_rate}%
      - Trend: #{trend.humanize}
      - Tasks Analyzed: #{@insights[:tasks_analyzed]}
      
      ## Key Observations
      #{generate_observations}
      
      ## Areas for Improvement
      #{@insights[:gaps_identified].first(3).map { |g| "- #{g}" }.join("\n")}
    NOTE
  end

  def generate_observations
    observations = []
    
    if @insights[:failure_patterns].present?
      top_failure = @insights[:failure_patterns].first
      observations << "Most common failure type: #{top_failure[0]} (#{top_failure[1]} occurrences)"
    end
    
    if @insights[:feedback_analyzed] > 0
      observations << "Received #{@insights[:feedback_analyzed]} pieces of feedback this period"
    end
    
    observations.empty? ? "No significant observations" : observations.map { |o| "- #{o}" }.join("\n")
  end

  def generate_learning_note(gaps)
    <<~NOTE
      # Learning Note - #{Time.current.strftime('%Y-%m-%d')}
      
      ## Knowledge Gaps Identified
      #{gaps.first(5).map { |g| "- #{g}" }.join("\n")}
      
      ## Research Completed
      - Added #{@insights[:knowledge_added]} new knowledge documents
      
      ## Next Steps
      - Continue monitoring these areas
      - Apply learned patterns to future tasks
      - Request clarification when encountering similar situations
    NOTE
  end

  def generate_goal_note
    goals = []
    
    if @insights[:gaps_identified].any?
      goals << "Master the identified knowledge gaps through practice"
    end
    
    goals << "Maintain or improve success rate"
    goals << "Provide clearer explanations to users"
    
    if @insights[:failure_patterns]&.key?('API/Integration Issues')
      goals << "Improve API error handling and retry logic"
    end
    
    <<~NOTE
      # Goals for Next Period - #{Time.current.strftime('%Y-%m-%d')}
      
      ## Objectives
      #{goals.map { |g| "- #{g}" }.join("\n")}
      
      ## Focus Areas
      - Quality over speed
      - Verify before acting
      - Learn from failures
      
      ## Reminder
      I am here to help users succeed. Every task is an opportunity to learn and improve.
    NOTE
  end

  def detect_domain_config
    AgentTrainingService::DOMAIN_KNOWLEDGE.each do |domain, config|
      if agent.slug.to_s.include?(domain) || 
         agent.name.to_s.downcase.include?(domain) ||
         agent.configuration&.dig('integration_slug').to_s == domain
        return config.merge(domain: domain)
      end
    end
    nil
  end

  def log_event(message)
    Rails.logger.info "[AgentReflection] #{message}"
    @reflection_log << { time: Time.current, message: message }
  end
end

