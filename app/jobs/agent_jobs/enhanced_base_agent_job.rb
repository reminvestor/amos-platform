# Enhanced Base Agent Job with MO Framework
module AgentJobs
  class EnhancedBaseAgentJob < BaseAgentJob
    include AgentModusOperandi
    include AgentModusOperandi::Procedures
    
    # Standard agent execution flow
    def execute_agent_task
      Rails.logger.info "[#{agent_name}] Starting enhanced agent execution"
      
      # Phase 1: Gather all available context
      context = gather_context
      
      # Phase 2: Determine what information we need
      required_info = determine_required_information(context)
      
      # Phase 3: Try to self-answer using RAG and inference
      self_answered = self_answer_questions(required_info[:questions], context)
      
      # Merge self-answered data into context
      context[:gathered] = self_answered[:answered]
      
      # Phase 4: Interactive questioning for remaining questions
      if self_answered[:remaining].any? && agent_config[:interactive]
        user_answers = interactive_questioning(self_answered[:remaining], context)
        context[:gathered].merge!(user_answers)
      end
      
      # Phase 5: Execute the task with full context
      execute_with_context(context)
    end
    
    protected
    
    # Override these in subclasses
    def determine_required_information(context)
      raise NotImplementedError, "Subclasses must implement determine_required_information"
    end
    
    def perform_task(context)
      raise NotImplementedError, "Subclasses must implement perform_task"
    end
    
    # Helper methods
    def agent_name
      agent_config[:name] || self.class.name.demodulize
    end
    
    def load_entity_context
      entity = Entity.find(@context[:entity_id])
      {
        entity_object: entity,
        id: entity.id,
        name: entity.name,
        subdomain: entity.subdomain,
        settings: entity.settings || {},
        metadata: entity.metadata || {}
      }
    end
    
    def load_user_context
      if user_id = @context[:user_id]
        user = User.find(user_id)
        {
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role
        }
      else
        {}
      end
    end
    
    def load_business_context
      entity = Entity.find(@context[:entity_id])
      user = entity.users.first
      
      context = {
        entity_name: entity.name,
        subdomain: entity.subdomain
      }
      
      if profile = user&.business_profile
        context.merge!(
          description: profile.description,
          industry: profile.industry,
          target_audience: profile.target_audience,
          tone_of_voice: profile.tone_of_voice,
          unique_value: profile.unique_value
        )
      end
      
      context
    end
    
    def load_settings_context
      entity = Entity.find(@context[:entity_id])
      settings = entity.settings || {}
      
      {
        primary_color: settings['primary_color'],
        secondary_color: settings['secondary_color'],
        logo_url: settings['logo_url'],
        brand_voice: settings['brand_voice'],
        style_guide: settings['style_guide'],
        font_family: settings['font_family'],
        all_settings: settings
      }
    end
    
    def load_interaction_history
      # Load recent interactions if available
      if @context[:recent_messages]
        @context[:recent_messages].last(10)
      else
        []
      end
    end
    
    def query_rag_for_context
      return {} unless agent_config[:rag_enabled]
      
      begin
        entity = Entity.find(@context[:entity_id])
        rag = HybridRAGQueryService.new(entity)
        
        # Build comprehensive query
        query_terms = [
          entity.name,
          "business description",
          "services products",
          "target audience",
          "value proposition",
          "features benefits",
          @task  # Include the current task
        ].join(" ")
        
        results = rag.search(
          query: query_terms,
          top_k: 10,
          include_system: true
        )
        
        if results[:chunks] && results[:chunks].any?
          {
            content: results[:chunks].map { |c| c[:content] || c[:chunk_text] }.join("\n\n"),
            sources: results[:chunks].map { |c| c[:source] || "Business documents" }.uniq,
            chunk_count: results[:chunks].size
          }
        else
          {}
        end
      rescue => e
        Rails.logger.error "[#{agent_name}] RAG context query failed: #{e.message}"
        {}
      end
    end
    
    def log_context_summary(context)
      Rails.logger.info "[#{agent_name}] Context gathered:"
      Rails.logger.info "  - Entity: #{context[:entity][:name]}"
      Rails.logger.info "  - Business: #{context[:business][:industry] || 'Unknown industry'}"
      Rails.logger.info "  - Settings: #{context[:settings].keys.size} settings loaded"
      Rails.logger.info "  - RAG: #{context[:rag][:chunk_count] || 0} documents found"
      Rails.logger.info "  - History: #{context[:history].size} recent messages"
    end
    
    def log_execution_context(context)
      Rails.logger.info "[#{agent_name}] Executing with context:"
      Rails.logger.info "  - Gathered fields: #{context[:gathered].keys.join(', ')}"
      Rails.logger.info "  - RAG content: #{context[:rag][:content].present? ? 'Yes' : 'No'}"
      Rails.logger.info "  - Business context: #{context[:business].keys.join(', ')}"
    end
    
    def find_in_context(field, context)
      # Check multiple places in context
      field_str = field.to_s
      
      # Direct match in gathered data
      return context[:gathered][field] if context[:gathered] && context[:gathered][field]
      
      # Check business context
      return context[:business][field] if context[:business] && context[:business][field]
      
      # Check settings
      return context[:settings][field_str] if context[:settings] && context[:settings][field_str]
      
      # Check entity metadata
      if context[:entity] && context[:entity][:metadata]
        return context[:entity][:metadata][field_str] if context[:entity][:metadata][field_str]
      end
      
      nil
    end
    
    def infer_answer(question, context)
      # Try to infer answers from available data
      case question[:field]
      when :headline
        if context[:business][:description]
          "Transform Your Business with #{context[:entity][:name]}"
        end
      when :target_audience
        context[:business][:target_audience] || infer_from_industry(context[:business][:industry])
      when :tone_of_voice
        context[:business][:tone_of_voice] || context[:settings][:brand_voice] || "professional"
      else
        nil
      end
    end
    
    def get_default_answer(question, context)
      # Provide sensible defaults for non-critical questions
      return nil if question[:critical]
      
      case question[:field]
      when :call_to_action
        "Get Started"
      when :headline
        "Welcome to #{context[:entity][:name]}"
      when :tone_of_voice
        "professional"
      else
        nil
      end
    end
    
    def infer_from_industry(industry)
      return nil unless industry
      
      case industry.downcase
      when /tech|software|saas/
        "Businesses looking for innovative technology solutions"
      when /health|medical|wellness/
        "Healthcare providers and wellness-conscious individuals"
      when /education|learning/
        "Students, educators, and lifelong learners"
      when /finance|banking|investment/
        "Individuals and businesses seeking financial growth"
      else
        "Businesses and individuals seeking quality solutions"
      end
    end
    
    def format_question_with_context(question, context)
      # Format the question with helpful context
      prompt = question[:question]
      
      if question[:why]
        prompt += "\n\n💡 Why this matters: #{question[:why]}"
      end
      
      if question[:suggestions] && question[:suggestions].any?
        prompt += "\n\n📝 Examples: #{question[:suggestions].join(', ')}"
      end
      
      # Add context hints if available
      if hint = generate_contextual_hint(question, context)
        prompt += "\n\n💭 Hint: #{hint}"
      end
      
      prompt
    end
    
    def generate_contextual_hint(question, context)
      # Generate hints based on what we know
      case question[:field]
      when :target_audience
        if industry = context[:business][:industry]
          "Consider who typically needs #{industry} solutions"
        end
      when :headline
        if value_prop = context[:business][:unique_value]
          "Think about highlighting: #{value_prop}"
        end
      else
        nil
      end
    end
    
    def process_user_answer(answer, question)
      # Clean and validate the answer
      cleaned = answer.to_s.strip
      
      # Apply any field-specific processing
      case question[:field]
      when :call_to_action
        # Extract CTA intent
        process_cta_input(cleaned)
      when :key_benefits, :features
        # Split into list if needed
        cleaned.split(/[,\n]/).map(&:strip).reject(&:blank?)
      else
        cleaned
      end
    end
    
    def process_cta_input(input)
      # Clean up CTA input
      cleaned = input.strip
      
      # Remove common prefixes
      cleaned = cleaned.gsub(/^(let'?s go with|make it say|use)\s+/i, '')
      
      # Ensure proper formatting
      cleaned.split.map(&:capitalize).join(' ')
    end
    
    # Stream content to user (inherited from BaseAgentJob)
    def stream_content(content)
      stream_to_amos({
        type: 'content',
        content: content
      })
    end
  end
end
