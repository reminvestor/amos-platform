# Landing Page Agent V2 - Using the MO Framework
module AgentJobs
  class LandingPageAgentJobV2 < EnhancedBaseAgentJob
    include LlmJsonParser
    
    # Configure agent using DSL
    configure_agent do
      name "Landing Page Agent"
      description "Creates high-converting landing pages with AI-driven content"
      capabilities :content_generation, :design_application, :conversion_optimization
      requires :business_context, :brand_guidelines, :target_audience
      rag_enabled true
      interactive true
      max_questions 3
      question_priority :smart
    end
    
    protected
    
    def determine_required_information(context)
      # Analyze what type of landing page we're creating
      page_intent = analyze_landing_page_intent(context)
      
      # Use LLM to generate intelligent questions based on ALL context
      questions = generate_intelligent_questions(page_intent, context)
      
      { 
        questions: questions,
        page_intent: page_intent
      }
    end
    
    def perform_task(context)
      # Extract all gathered information
      info = build_complete_info(context)
      
      # Create the landing page
      update_status('running', 'Creating your landing page with all gathered context...', progress: 40)
      
      landing_page = create_landing_page(info)
      
      # Generate content using LLM with full context
      update_status('running', 'Generating AI-powered content...', progress: 60)
      content_structure = generate_content_with_full_context(info, context)
      
      # Convert to HTML with dynamic styling
      landing_page.html_content = convert_to_styled_html(content_structure, info)
      
      # Apply styling and save
      apply_dynamic_styling(landing_page, info)
      finalize_and_save(landing_page, content_structure)
      
      # Return success result
      build_success_result(landing_page)
    end
    
    private
    
    def analyze_landing_page_intent(context)
      request_text = @task.downcase
      
      page_type = case request_text
      when /product/
        :product
      when /service/
        :service
      when /event|webinar|conference/
        :event
      when /newsletter|subscribe/
        :newsletter
      when /contact|reach out/
        :contact
      else
        :general
      end
      
      {
        type: page_type,
        raw_request: @task,
        context_clues: extract_context_clues(request_text)
      }
    end
    
    def generate_intelligent_questions(intent, context)
      # Build comprehensive context for question generation
      system_prompt = <<~PROMPT
        You are an expert landing page strategist. Your job is to determine what specific 
        information is still needed to create a high-converting landing page.
        
        YOU HAVE ACCESS TO THE FOLLOWING CONTEXT:
        
        Business Information:
        #{format_business_context(context[:business])}
        
        Brand Guidelines:
        #{format_brand_context(context[:settings])}
        
        RAG Knowledge Base:
        #{context[:rag][:content].present? ? context[:rag][:content][0..500] : "No additional context found"}
        
        Previous Answers:
        #{context[:gathered]&.map { |k,v| "#{k}: #{v}" }&.join("\n")}
        
        IMPORTANT: Only ask for information that is NOT already available in the context above.
        If you can infer or find the answer in the provided context, DO NOT ask for it.
        
        The user wants to create a #{intent[:type]} landing page.
        
        Generate 0-4 ESSENTIAL questions that:
        1. Are NOT already answered in the context
        2. Would significantly improve the landing page
        3. Are specific and actionable
        4. Cannot be inferred from existing data
        
        #{LlmJsonParser::JSON_FORMAT_INSTRUCTIONS}
        
        Return JSON array (empty array if no questions needed):
        [
          {
            "field": "unique_field_name",
            "question": "Specific question",
            "why": "Why this matters",
            "critical": true/false,
            "suggestions": ["example1", "example2"]
          }
        ]
      PROMPT
      
      user_message = "Determine what information is still needed for a #{intent[:type]} landing page."
      
      begin
        Rails.logger.info "[LandingPageAgentV2] Generating questions with full context"
        Rails.logger.info "[LandingPageAgentV2] Business context keys: #{context[:business].keys.join(', ')}"
        Rails.logger.info "[LandingPageAgentV2] Has RAG content: #{context[:rag][:content].present?}"
        
        response = call_llm_for_questions(system_prompt, user_message)
        questions = parse_json_from_llm(response, context: "LandingPageAgentV2")
        
        Rails.logger.info "[LandingPageAgentV2] Generated #{questions.size} questions after context analysis"
        questions
      rescue => e
        Rails.logger.error "[LandingPageAgentV2] Question generation failed: #{e.message}"
        # Return minimal fallback questions
        fallback_questions_for_intent(intent[:type])
      end
    end
    
    def format_business_context(business)
      lines = []
      lines << "- Name: #{business[:entity_name]}" if business[:entity_name]
      lines << "- Industry: #{business[:industry]}" if business[:industry]
      lines << "- Description: #{business[:description]}" if business[:description]
      lines << "- Target Audience: #{business[:target_audience]}" if business[:target_audience]
      lines << "- Value Proposition: #{business[:unique_value]}" if business[:unique_value]
      lines << "- Tone: #{business[:tone_of_voice]}" if business[:tone_of_voice]
      
      lines.any? ? lines.join("\n") : "No business information available"
    end
    
    def format_brand_context(settings)
      lines = []
      lines << "- Primary Color: #{settings[:primary_color]}" if settings[:primary_color]
      lines << "- Brand Voice: #{settings[:brand_voice]}" if settings[:brand_voice]
      lines << "- Style Guide: #{settings[:style_guide]}" if settings[:style_guide]
      lines << "- Logo: #{settings[:logo_url].present? ? 'Available' : 'Not set'}"
      
      lines.any? ? lines.join("\n") : "No brand guidelines available"
    end
    
    def build_complete_info(context)
      # Merge all context sources
      info = {
        # Basic entity info
        entity_id: context[:entity][:id],
        entity_name: context[:entity][:name],
        subdomain: context[:entity][:subdomain],
        user_id: context[:user][:id],
        
        # Business context
        business_name: context[:business][:entity_name],
        industry: context[:business][:industry],
        description: context[:business][:description],
        target_audience: context[:business][:target_audience] || context[:gathered][:target_audience],
        value_proposition: context[:business][:unique_value] || context[:business][:description],
        tone_of_voice: context[:business][:tone_of_voice] || context[:settings][:brand_voice],
        
        # Styling
        primary_color: context[:settings][:primary_color],
        secondary_color: context[:settings][:secondary_color],
        logo_url: context[:settings][:logo_url],
        brand_voice: context[:settings][:brand_voice],
        style_guide: context[:settings][:style_guide],
        font_family: context[:settings][:font_family],
        
        # RAG context
        rag_context: context[:rag][:content],
        rag_sources: context[:rag][:sources],
        
        # User provided answers
        **context[:gathered]
      }.compact
      
      # Set defaults for critical fields
      info[:headline] ||= "Transform Your Business with #{info[:entity_name]}"
      info[:call_to_action] ||= "Get Started"
      info[:page_type] = context[:required_info][:page_intent][:type]
      
      Rails.logger.info "[LandingPageAgentV2] Built complete info with #{info.keys.size} fields"
      info
    end
    
    def generate_content_with_full_context(info, context)
      system_prompt = build_comprehensive_system_prompt()
      user_message = build_content_generation_message(info, context)
      
      Rails.logger.info "[LandingPageAgentV2] Generating content with:"
      Rails.logger.info "  - Business fields: #{info.keys.select { |k| info[k].present? }.size}"
      Rails.logger.info "  - RAG context: #{info[:rag_context]&.size || 0} chars"
      Rails.logger.info "  - Brand guidelines: #{[info[:primary_color], info[:brand_voice], info[:style_guide]].compact.size} items"
      
      begin
        response = call_llm_for_content(system_prompt, user_message, info)
        content = parse_json_from_llm(response, context: "LandingPageAgentV2")
        
        Rails.logger.info "[LandingPageAgentV2] Generated content structure with #{content.keys.size} sections"
        content
      rescue => e
        Rails.logger.error "[LandingPageAgentV2] Content generation failed: #{e.message}"
        build_fallback_content(info)
      end
    end
    
    def build_comprehensive_system_prompt
      <<~PROMPT
        You are an elite landing page copywriter and conversion optimization expert. 
        Your landing pages consistently achieve 15%+ conversion rates.
        
        CREATE A HIGH-CONVERTING LANDING PAGE following these principles:
        
        🎯 CONVERSION PSYCHOLOGY:
        - Hook visitors in the first 3 seconds
        - Address their #1 pain point immediately
        - Use the PAS framework (Problem-Agitate-Solution)
        - Build trust with specificity and social proof
        - Create urgency without being pushy
        
        📝 CONTENT REQUIREMENTS:
        - REAL, SPECIFIC content - no placeholders
        - Every paragraph must be 80+ words
        - Use ALL provided business context
        - Incorporate RAG knowledge base insights
        - Follow brand voice and guidelines exactly
        
        🎨 STRUCTURE:
        Your response must include:
        1. Hero section with compelling headline and subheadline
        2. Problem/pain point section
        3. Solution presentation
        4. Benefits section (not features)
        5. Social proof or trust indicators
        6. Clear call-to-action
        
        #{LlmJsonParser::JSON_FORMAT_INSTRUCTIONS}
        
        Return a JSON structure with all sections filled with rich, persuasive content.
      PROMPT
    end
    
    def build_content_generation_message(info, context)
      <<~MESSAGE
        Create a #{info[:page_type]} landing page for:
        
        BUSINESS INFORMATION:
        Name: #{info[:entity_name]}
        Industry: #{info[:industry] || 'Not specified'}
        Description: #{info[:description] || info[:value_proposition]}
        Target Audience: #{info[:target_audience]}
        Unique Value: #{info[:value_proposition]}
        
        BRAND GUIDELINES:
        Primary Color: #{info[:primary_color] || '#667eea'}
        Brand Voice: #{info[:brand_voice] || info[:tone_of_voice] || 'professional'}
        Style Guide: #{info[:style_guide] || 'Modern and clean'}
        
        USER REQUIREMENTS:
        Headline: #{info[:headline]} (if provided, use as inspiration)
        Call to Action: #{info[:call_to_action]}
        #{info[:message] ? "Core Message: #{info[:message]}" : ""}
        #{info[:key_benefits] ? "Key Benefits: #{info[:key_benefits].join(', ')}" : ""}
        
        KNOWLEDGE BASE CONTEXT:
        #{info[:rag_context] ? info[:rag_context][0..1500] : "No additional context available"}
        
        Create compelling, conversion-focused content that incorporates ALL this information.
        Make it specific to #{info[:entity_name]} and their unique value proposition.
      MESSAGE
    end
    
    def call_llm_for_questions(system_prompt, user_message)
      bedrock = BedrockService.new
      bedrock.send_message(
        system_prompt,
        [{ role: "user", content: user_message }],
        model: selected_model,
        temperature: 0.3,
        max_tokens: 1000
      )
    end
    
    def call_llm_for_content(system_prompt, user_message, info)
      bedrock = BedrockService.new
      bedrock.send_message(
        system_prompt,
        [{ role: "user", content: user_message }],
        model: selected_model,
        temperature: 0.7,
        max_tokens: 4000,
        response_format: { type: "json_object" }
      )
    end
    
    def selected_model
      @context[:recent_messages]&.last&.dig(:metadata, :model_preference) || 
      @context[:metadata]&.dig(:model_preference) || 
      "claude-haiku-4-5-20251001"
    end
    
    def fallback_questions_for_intent(page_type)
      case page_type
      when :product
        [
          {
            field: :product_name,
            question: "What's the name of your product?",
            critical: true,
            why: "Helps create focused messaging"
          }
        ]
      when :service
        [
          {
            field: :service_name,
            question: "What service are you offering?",
            critical: true,
            why: "Essential for clear communication"
          }
        ]
      else
        []  # No questions for general pages if we have context
      end
    end
    
    # Remaining helper methods...
    def create_landing_page(info)
      LandingPage.create!(
        entity_id: info[:entity_id],
        user_id: info[:user_id],
        title: info[:headline] || "Landing Page",
        slug: generate_unique_slug(info),
        description: info[:value_proposition] || info[:description] || "Welcome",
        status: 'draft',
        metadata: {
          page_type: info[:page_type],
          generated_with: 'v2_mo_framework'
        }
      )
    end
    
    def generate_unique_slug(info)
      base = info[:headline] || info[:product_name] || info[:service_name] || "page"
      base_slug = base.parameterize
      timestamp = Time.current.strftime("%Y%m%d-%H%M%S")
      "#{base_slug}-#{timestamp}"
    end
    
    def convert_to_styled_html(content, info)
      # Implementation from original agent
      # ... (reuse existing HTML generation logic)
    end
    
    def apply_dynamic_styling(landing_page, info)
      style_settings = {
        primary_color: info[:primary_color] || "#667eea",
        secondary_color: info[:secondary_color] || "#764ba2",
        font_family: info[:font_family] || "system-ui",
        brand_voice: info[:brand_voice] || "professional",
        logo_url: info[:logo_url]
      }
      
      landing_page.update!(
        metadata: landing_page.metadata.merge(style_settings: style_settings)
      )
    end
    
    def finalize_and_save(landing_page, content_structure)
      landing_page.update!(
        metadata: landing_page.metadata.merge(
          content_structure: content_structure,
          generated_at: Time.current
        )
      )
    end
    
    def build_success_result(landing_page)
      entity = Entity.find(landing_page.entity_id)
      preview_url = "/l/#{entity.subdomain}/#{landing_page.slug}"
      
      update_status('completed', 'Landing page created successfully!', progress: 100)
      
      {
        success: true,
        landing_page_id: landing_page.id,
        preview_url: preview_url,
        message: "✨ Your landing page is ready!\n\n" +
                 "📄 View it at: #{preview_url}\n\n" +
                 "I'm loading the editor for you now so you can make any adjustments..."
      }
    end
    
    def build_fallback_content(info)
      # Fallback content structure
      {
        hero: {
          headline: info[:headline] || "Welcome to #{info[:entity_name]}",
          subheadline: info[:value_proposition] || "Transform your business with our solutions",
          cta_text: info[:call_to_action] || "Get Started"
        },
        sections: [
          {
            type: "benefits",
            title: "Why Choose Us",
            content: "We provide innovative solutions tailored to your needs..."
          }
        ]
      }
    end
    
    def extract_context_clues(text)
      clues = []
      clues << "urgency" if text.match?(/urgent|asap|quickly|now/)
      clues << "promotional" if text.match?(/sale|discount|offer|deal/)
      clues << "informational" if text.match?(/learn|discover|explore/)
      clues
    end
  end
end
