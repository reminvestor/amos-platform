# Agent Modus Operandi (MO) Framework
# This defines the standard operating procedures and guidelines for all agents
module AgentModusOperandi
  extend ActiveSupport::Concern
  
  included do
    # Core MO configuration
    class_attribute :agent_config
    self.agent_config = {
      name: nil,
      description: nil,
      capabilities: [],
      required_context: [],
      rag_enabled: true,
      interactive: true,
      max_questions: 5,
      question_priority: :smart  # :all, :critical, :smart
    }
  end
  
  class_methods do
    # DSL for defining agent configuration
    def configure_agent(&block)
      config = AgentConfiguration.new(agent_config)
      config.instance_eval(&block)
      self.agent_config = config.to_h
    end
  end
  
  # Standard Operating Procedures
  module Procedures
    # Phase 1: Context Gathering
    def gather_context
      Rails.logger.info "[#{agent_name}] Phase 1: Gathering context"
      
      context = {
        entity: load_entity_context,
        user: load_user_context,
        business: load_business_context,
        rag: query_rag_for_context,
        settings: load_settings_context,
        history: load_interaction_history
      }
      
      log_context_summary(context)
      context
    end
    
    # Phase 2: Self-Answer Questions
    def self_answer_questions(questions, context)
      Rails.logger.info "[#{agent_name}] Phase 2: Attempting to self-answer #{questions.size} questions"
      
      answered = {}
      remaining = []
      
      questions.each do |question|
        answer = attempt_self_answer(question, context)
        
        if answer[:found]
          Rails.logger.info "[#{agent_name}] Self-answered: #{question[:field]} = #{answer[:value]}"
          answered[question[:field]] = answer[:value]
        else
          Rails.logger.info "[#{agent_name}] Could not self-answer: #{question[:field]}"
          remaining << question
        end
      end
      
      { answered: answered, remaining: remaining }
    end
    
    # Phase 3: Interactive Questioning (if needed)
    def interactive_questioning(remaining_questions, context)
      return {} if remaining_questions.empty? || !agent_config[:interactive]
      
      Rails.logger.info "[#{agent_name}] Phase 3: Interactive questioning for #{remaining_questions.size} questions"
      
      # Prioritize questions based on configuration
      prioritized = prioritize_questions(remaining_questions, context)
      
      # Ask only the most important questions
      answers = {}
      prioritized.each_with_index do |question, index|
        break if index >= agent_config[:max_questions]
        
        answer = request_user_input(
          format_question_with_context(question, context),
          options: question[:suggestions]
        )
        
        answers[question[:field]] = process_user_answer(answer, question)
      end
      
      answers
    end
    
    # Phase 4: Execution
    def execute_with_context(full_context)
      Rails.logger.info "[#{agent_name}] Phase 4: Executing with full context"
      
      # Log what we have
      log_execution_context(full_context)
      
      # Execute the specific agent task
      perform_task(full_context)
    end
    
    private
    
    def attempt_self_answer(question, context)
      # Try multiple strategies to answer the question
      
      # Strategy 1: Check if already in context
      if value = find_in_context(question[:field], context)
        return { found: true, value: value, source: 'context' }
      end
      
      # Strategy 2: Query RAG with specific question
      if agent_config[:rag_enabled]
        rag_answer = query_rag_for_answer(question, context)
        if rag_answer[:found]
          return { found: true, value: rag_answer[:value], source: 'rag' }
        end
      end
      
      # Strategy 3: Infer from available data
      if inferred = infer_answer(question, context)
        return { found: true, value: inferred, source: 'inference' }
      end
      
      # Strategy 4: Use sensible defaults for non-critical questions
      if default = get_default_answer(question, context)
        return { found: true, value: default, source: 'default' }
      end
      
      { found: false }
    end
    
    def query_rag_for_answer(question, context)
      return { found: false } unless defined?(HybridRAGQueryService)
      
      begin
        entity = context[:entity][:entity_object]
        rag = HybridRAGQueryService.new(entity)
        
        # Create a specific query for this question
        query = build_rag_query_for_question(question, context)
        
        results = rag.search(
          query: query,
          top_k: 3,
          include_system: true
        )
        
        if results[:chunks] && results[:chunks].any?
          # Try to extract answer from RAG results
          answer = extract_answer_from_rag(results[:chunks], question)
          if answer
            Rails.logger.info "[#{agent_name}] Found answer in RAG for #{question[:field]}: #{answer}"
            return { found: true, value: answer }
          end
        end
      rescue => e
        Rails.logger.error "[#{agent_name}] RAG query for answer failed: #{e.message}"
      end
      
      { found: false }
    end
    
    def build_rag_query_for_question(question, context)
      # Build a targeted query based on the question and context
      base_query = question[:question]
      
      # Add context to make query more specific
      contextual_parts = []
      contextual_parts << context[:entity][:name] if context[:entity][:name]
      contextual_parts << context[:business][:industry] if context[:business][:industry]
      contextual_parts << question[:field].to_s.humanize
      
      "#{base_query} #{contextual_parts.join(' ')}"
    end
    
    def extract_answer_from_rag(chunks, question)
      # Use LLM to extract specific answer from RAG chunks
      # This is a simplified version - could be enhanced with LLM
      
      combined_text = chunks.map { |c| c[:content] || c[:chunk_text] }.join("\n")
      
      # Simple extraction based on field type
      case question[:field]
      when :headline, :tagline
        # Look for existing headlines or taglines
        if match = combined_text.match(/(?:headline|tagline|slogan)[:：]\s*(.+?)(?:\n|$)/i)
          return match[1].strip
        end
      when :target_audience
        if match = combined_text.match(/(?:target audience|customers?|clients?)[:：]\s*(.+?)(?:\n|$)/i)
          return match[1].strip
        end
      when :value_proposition
        if match = combined_text.match(/(?:value proposition|what we offer|benefits?)[:：]\s*(.+?)(?:\n|$)/i)
          return match[1].strip
        end
      end
      
      nil
    end
    
    def prioritize_questions(questions, context)
      case agent_config[:question_priority]
      when :all
        questions
      when :critical
        questions.select { |q| q[:critical] }
      when :smart
        # Score questions based on importance and what we already know
        questions.sort_by { |q| calculate_question_importance(q, context) }.reverse
      else
        questions
      end
    end
    
    def calculate_question_importance(question, context)
      score = 0
      
      # Higher score for critical questions
      score += 10 if question[:critical]
      
      # Lower score if we have partial information
      score -= 5 if partial_answer_exists?(question[:field], context)
      
      # Higher score for questions that unlock other features
      score += 5 if question[:unlocks]
      
      # Adjust based on page/task type
      score += relevance_to_task(question, context)
      
      score
    end
  end
  
  # Configuration DSL
  class AgentConfiguration
    attr_reader :config
    
    def initialize(initial_config)
      @config = initial_config.dup
    end
    
    def name(value)
      @config[:name] = value
    end
    
    def description(value)
      @config[:description] = value
    end
    
    def capabilities(*values)
      @config[:capabilities] = values
    end
    
    def requires(*values)
      @config[:required_context] = values
    end
    
    def rag_enabled(value = true)
      @config[:rag_enabled] = value
    end
    
    def interactive(value = true)
      @config[:interactive] = value
    end
    
    def max_questions(value)
      @config[:max_questions] = value
    end
    
    def question_priority(value)
      @config[:question_priority] = value
    end
    
    def to_h
      @config
    end
  end
end
