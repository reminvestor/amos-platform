# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           ⚠️ DEPRECATED ⚠️                                  ║
# ╠════════════════════════════════════════════════════════════════════════════╣
# ║ This file is DEPRECATED as of 2026-01-24.                                   ║
# ║                                                                             ║
# ║ With the Plugin Injection architecture, learning is now handled by:         ║
# ║ - LoadoutOptimizationService - tracks and optimizes loadouts                 ║
# ║ - LoadoutMetric - stores performance data                                    ║
# ║                                                                             ║
# ║ DO NOT USE THIS FILE FOR NEW CODE.                                          ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Agent Learning Service - Helps agents learn from interactions
# DEPRECATED: Use LoadoutOptimizationService instead
class AgentLearningService
  def initialize(agent_type)
    @agent_type = agent_type
  end
  
  # Analyze successful interactions to extract patterns
  def learn_from_success(job_record, context, result)
    # Extract what made this interaction successful
    patterns = extract_success_patterns(job_record, context, result)
    
    # Store patterns for future use
    store_learning_patterns(patterns)
    
    # Update agent's knowledge base
    update_agent_knowledge(patterns)
  end
  
  # Learn from failures to avoid mistakes
  def learn_from_failure(job_record, context, error)
    # Analyze what went wrong
    failure_analysis = analyze_failure(job_record, context, error)
    
    # Store failure patterns
    store_failure_patterns(failure_analysis)
    
    # Update agent guidelines
    update_agent_guidelines(failure_analysis)
  end
  
  # Get learned patterns for a specific context
  def get_learned_patterns(context)
    # Retrieve relevant patterns
    patterns = retrieve_patterns(context)
    
    # Apply machine learning to rank patterns
    ranked_patterns = rank_patterns_by_relevance(patterns, context)
    
    # Return top patterns
    ranked_patterns.first(5)
  end
  
  # Suggest improvements to agent configuration
  def suggest_improvements(agent_definition)
    # Analyze past performance
    performance = analyze_agent_performance(agent_definition)
    
    # Generate improvement suggestions
    suggestions = []
    
    if performance[:question_abandonment_rate] > 0.3
      suggestions << {
        type: 'reduce_questions',
        reason: 'High abandonment rate detected',
        recommendation: 'Reduce max_questions or improve question relevance'
      }
    end
    
    if performance[:rag_hit_rate] < 0.5
      suggestions << {
        type: 'improve_rag_queries',
        reason: 'Low RAG utilization',
        recommendation: 'Enhance RAG query generation for better self-answering'
      }
    end
    
    if performance[:avg_completion_time] > 300 # 5 minutes
      suggestions << {
        type: 'optimize_workflow',
        reason: 'Slow task completion',
        recommendation: 'Streamline workflow or reduce processing steps'
      }
    end
    
    suggestions
  end
  
  private
  
  def extract_success_patterns(job_record, context, result)
    {
      agent_type: @agent_type,
      task_type: job_record.input_data['task'],
      context_keys: context.keys,
      questions_asked: job_record.input_data['questions_asked'] || [],
      self_answered: job_record.input_data['self_answered'] || [],
      execution_time: job_record.completed_at - job_record.created_at,
      user_satisfaction: estimate_satisfaction(result),
      successful_prompts: extract_successful_prompts(job_record),
      rag_queries: job_record.input_data['rag_queries'] || []
    }
  end
  
  def analyze_failure(job_record, context, error)
    {
      agent_type: @agent_type,
      error_type: error.class.name,
      error_message: error.message,
      context_state: context.slice(:entity_id, :user_id),
      missing_data: identify_missing_data(job_record, error),
      failed_at_stage: job_record.input_data['last_stage'] || 'unknown'
    }
  end
  
  def store_learning_patterns(patterns)
    # Store in a dedicated learning table or cache
    Rails.cache.write(
      "agent_patterns:#{@agent_type}:#{Time.current.to_i}",
      patterns,
      expires_in: 30.days
    )
    
    # Also persist important patterns to database
    if patterns[:user_satisfaction] > 0.8
      AgentLearningPattern.create!(
        agent_type: @agent_type,
        pattern_type: 'success',
        pattern_data: patterns,
        weight: patterns[:user_satisfaction]
      )
    end
  end
  
  def update_agent_knowledge(patterns)
    # Extract reusable knowledge
    if patterns[:successful_prompts].any?
      # Store successful prompts for reuse
      patterns[:successful_prompts].each do |prompt|
        AgentKnowledge.find_or_create_by(
          agent_type: @agent_type,
          knowledge_type: 'prompt_template',
          key: Digest::MD5.hexdigest(prompt[:context].to_s)
        ).update!(
          value: prompt[:template],
          usage_count: 1,
          success_rate: 1.0
        )
      end
    end
  end
  
  def retrieve_patterns(context)
    # Get patterns from last 30 days
    recent_patterns = Rails.cache.read("agent_patterns:#{@agent_type}:*") || []
    
    # Get persisted patterns
    db_patterns = AgentLearningPattern
      .where(agent_type: @agent_type)
      .where(created_at: 30.days.ago..)
      .order(weight: :desc)
      .limit(100)
    
    # Combine and deduplicate
    (recent_patterns + db_patterns.map(&:pattern_data)).uniq
  end
  
  def rank_patterns_by_relevance(patterns, context)
    # Simple relevance scoring
    patterns.map do |pattern|
      score = calculate_relevance_score(pattern, context)
      { pattern: pattern, score: score }
    end.sort_by { |p| -p[:score] }.map { |p| p[:pattern] }
  end
  
  def calculate_relevance_score(pattern, context)
    score = 0.0
    
    # Context similarity
    shared_keys = (pattern[:context_keys] & context.keys).size
    total_keys = pattern[:context_keys].size
    score += (shared_keys.to_f / total_keys) * 0.3 if total_keys > 0
    
    # Task similarity
    if pattern[:task_type] && context[:task]
      task_similarity = calculate_text_similarity(
        pattern[:task_type].to_s,
        context[:task].to_s
      )
      score += task_similarity * 0.3
    end
    
    # Success weight
    score += (pattern[:user_satisfaction] || 0.5) * 0.4
    
    score
  end
  
  def calculate_text_similarity(text1, text2)
    # Simple word overlap similarity
    words1 = text1.downcase.split(/\W+/)
    words2 = text2.downcase.split(/\W+/)
    
    intersection = (words1 & words2).size
    union = (words1 | words2).size
    
    return 0.0 if union == 0
    intersection.to_f / union
  end
  
  def estimate_satisfaction(result)
    # Estimate based on various factors
    score = 0.5  # Base score
    
    # Quick completion is good
    if result[:completion_time] && result[:completion_time] < 60
      score += 0.2
    end
    
    # No errors is good
    if result[:errors].nil? || result[:errors].empty?
      score += 0.2
    end
    
    # Minimal questions asked is good
    if result[:questions_asked] && result[:questions_asked] < 2
      score += 0.1
    end
    
    [score, 1.0].min
  end
  
  def extract_successful_prompts(job_record)
    # Extract prompts that led to successful outcomes
    prompts = []
    
    if job_record.input_data['llm_interactions']
      job_record.input_data['llm_interactions'].each do |interaction|
        if interaction['success']
          prompts << {
            context: interaction['context'],
            template: interaction['prompt'],
            response_quality: interaction['quality_score'] || 0.7
          }
        end
      end
    end
    
    prompts
  end
  
  def identify_missing_data(job_record, error)
    missing = []
    
    # Check error message for clues
    if error.message.include?('missing') || error.message.include?('required')
      # Extract field names from error
      field_match = error.message.match(/field[s]?\s+(\w+)/)
      missing << field_match[1] if field_match
    end
    
    # Check job data for null required fields
    if job_record.input_data['required_fields']
      job_record.input_data['required_fields'].each do |field|
        if job_record.input_data['gathered_data'][field].nil?
          missing << field
        end
      end
    end
    
    missing
  end
  
  def analyze_agent_performance(agent_definition)
    # Get recent job records
    recent_jobs = Amos::JobRecord
      .where(agent_type: "custom_#{agent_definition.agent_type}")
      .where(created_at: 7.days.ago..)
      .where("input_data->>'agent_definition_id' = ?", agent_definition.id.to_s)
    
    total_jobs = recent_jobs.count
    return {} if total_jobs == 0
    
    completed_jobs = recent_jobs.where(status: 'completed')
    failed_jobs = recent_jobs.where(status: 'failed')
    
    # Calculate metrics
    {
      total_executions: total_jobs,
      success_rate: completed_jobs.count.to_f / total_jobs,
      failure_rate: failed_jobs.count.to_f / total_jobs,
      question_abandonment_rate: calculate_abandonment_rate(recent_jobs),
      rag_hit_rate: calculate_rag_hit_rate(completed_jobs),
      avg_completion_time: calculate_avg_completion_time(completed_jobs),
      common_errors: analyze_common_errors(failed_jobs)
    }
  end
  
  def calculate_abandonment_rate(jobs)
    abandoned = jobs.where(status: 'waiting_for_input')
      .where('updated_at < ?', 1.hour.ago)
      .count
    
    jobs.count > 0 ? abandoned.to_f / jobs.count : 0.0
  end
  
  def calculate_rag_hit_rate(jobs)
    total_questions = 0
    self_answered = 0
    
    jobs.each do |job|
      if job.input_data['questions_asked']
        total_questions += job.input_data['questions_asked'].size
      end
      if job.input_data['self_answered']
        self_answered += job.input_data['self_answered'].size
      end
    end
    
    total_questions > 0 ? self_answered.to_f / total_questions : 0.0
  end
  
  def calculate_avg_completion_time(jobs)
    times = jobs.map do |job|
      next unless job.completed_at
      job.completed_at - job.created_at
    end.compact
    
    times.any? ? times.sum / times.size : 0
  end
  
  def analyze_common_errors(failed_jobs)
    errors = Hash.new(0)
    
    failed_jobs.each do |job|
      if job.error_message
        error_type = job.error_message.split(':').first
        errors[error_type] += 1
      end
    end
    
    errors.sort_by { |_, count| -count }.first(5).to_h
  end
end

# Placeholder models for learning storage
# These would need actual implementations
class AgentLearningPattern < ApplicationRecord
  # Store successful patterns for reuse
end

class AgentKnowledge < ApplicationRecord
  # Store reusable knowledge pieces
end
