# Specialized agent for handling landing page creation
module AgentJobs
  class LandingPageAgentJob < BaseAgentJob
    include LlmJsonParser
    
    def execute_agent_task
      Rails.logger.info "[LandingPageAgent] Processing: #{@task}"
      Rails.logger.info "[LandingPageAgent] Context session_id: #{@context[:session_id]}"
      
      # Phase 1: Understanding intent and providing intelligent analysis
      update_status('running', 'Analyzing your request...', progress: 10)
      Rails.logger.info "[LandingPageAgent] Status update sent"
      intent = analyze_landing_page_request
      
      # Scout already provides the introduction - skip agent's initial analysis to avoid duplication
      # initial_analysis = generate_initial_analysis(intent)
      # stream_content(initial_analysis)
      # sleep(0.5) # Small delay to ensure message order
      
      # Phase 2: Gathering information with intelligent questions
      update_status('running', 'Preparing personalized questions for your landing page...', progress: 25)
      page_info = gather_page_information(intent)
      
      # Phase 3: Creating the page with AI
      update_status('running', 'Using AI to craft your unique landing page content...', progress: 60)
      landing_page = create_landing_page(page_info)
      
      # Phase 4: Finalizing
      update_status('running', 'Applying your brand settings and publishing...', progress: 90)
      finalize_page(landing_page)
      
      # Return result
      # Generate the URL
      entity = Entity.find(landing_page.entity_id)
      landing_page_url = "/l/#{entity.subdomain}/#{landing_page.slug}"
      
      {
        success: true,
        landing_page_id: landing_page.id,
        url: landing_page_url,
        message: "✅ Your landing page '#{landing_page.title}' has been created successfully!\n\n" +
                 "📄 View it at: #{landing_page_url}\n\n" +
                 "I'm loading the editor for you now so you can make any adjustments..."
      }
    end
    
    private
    
    def query_rag_for_business_info(business_name)
      Rails.logger.info "[LandingPageAgent] Querying RAG system for business info: #{business_name}"
      
      begin
        # Try HybridRAGQueryService first
        if defined?(HybridRAGQueryService)
          entity = Entity.find(@context[:entity_id])
          rag_service = HybridRAGQueryService.new(entity)
          
          # Search for relevant business information
          search_query = "#{business_name} business description services products target audience industry value proposition features benefits"
          results = rag_service.search(
            query: search_query,
            top_k: 5,
            include_system: true  # Include system documents about the business
          )
          
          if results[:chunks] && results[:chunks].any?
            # Combine the top results into context
            content_parts = []
            results[:chunks].each do |chunk|
              content_parts << chunk[:content] || chunk[:chunk_text]
            end
            
            content = content_parts.compact.join("\n\n---\n\n")
            
            sources = results[:chunks].map { |chunk| 
              chunk[:metadata]&.dig(:source) || chunk[:source] || "Business documents"
            }.uniq
            
            Rails.logger.info "[LandingPageAgent] Found #{results[:chunks].size} relevant documents via HybridRAG"
            
            return {
              content: content,
              sources: sources
            }
          else
            Rails.logger.info "[LandingPageAgent] No relevant documents found in HybridRAG"
          end
        else
          Rails.logger.warn "[LandingPageAgent] HybridRAG service not available"
        end
      rescue => e
        Rails.logger.error "[LandingPageAgent] RAG query failed: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
      end
      
      nil
    end
    
    def analyze_landing_page_request
      # Use context to understand what kind of landing page
      context_messages = @context[:recent_messages] || []
      
      # Check if user mentioned specific type
      request_text = @task.downcase
      
      intent = {
        page_type: detect_page_type(request_text),
        has_specific_content: request_text.match?(/about|product|service|pricing/i),
        urgency: request_text.match?(/quick|asap|now|fast/i) ? :high : :normal
      }
      
      intent
    end
    
    def detect_page_type(text)
      case text
      when /product/i then :product
      when /service/i then :service
      when /event|webinar/i then :event
      when /email|lead|capture/i then :lead_capture
      when /about/i then :about
      when /pricing/i then :pricing
      else :general
      end
    end
    
    def humanize_page_type(type)
      type.to_s.humanize.downcase
    end
    
    def generate_initial_analysis(intent)
      entity = Entity.find(@context[:entity_id])
      entity_name = entity.name
      
      analysis = "I'll create a professional #{humanize_page_type(intent[:page_type])} landing page for #{entity_name}. "
      
      # Add specific context based on page type
      case intent[:page_type]
      when :product
        analysis += "This page will showcase your product with compelling features, benefits, and social proof to drive conversions."
      when :service
        analysis += "I'll highlight your service's unique value proposition and build trust with potential clients."
      when :lead_capture
        analysis += "I'll design an effective lead capture form with a compelling offer to grow your contact list."
      when :about
        analysis += "I'll tell your company's story in a way that builds trust and connects with your audience."
      when :pricing
        analysis += "I'll create clear, persuasive pricing tables that guide visitors to the right plan."
      else
        analysis += "I'll craft compelling content that converts visitors into customers."
      end
      
      analysis += "\n\nI've analyzed your business profile and will:\n"
      analysis += "• Use AI to generate unique, conversion-focused content\n"
      analysis += "• Apply your brand colors and style guidelines automatically\n"
      analysis += "• Ask intelligent questions to ensure the page meets your specific needs\n\n"
      analysis += "Let me ask you a few targeted questions to make this perfect for your business..."
      
      analysis
    end
    
    def gather_page_information(intent)
      info = {
        page_type: intent[:page_type],
        entity_id: @context[:entity_id]
      }
      
      # Check what we already have from context
      entity_data = load_entity_data(info[:entity_id])
      
      # Merge entity data into info
      info = info.merge(entity_data)
      
      # Pre-fill from business profile
      info[:business_name] = entity_data[:name]
      info[:subdomain] = entity_data[:subdomain]
      
      if entity_data[:business_profile]
        profile = entity_data[:business_profile]
        info[:value_proposition] = profile[:description]
        info[:target_audience] = profile[:target_audience]
        info[:tone_of_voice] = profile[:tone_of_voice]
        info[:industry] = profile[:industry]
      end
      
      # Query RAG system for additional context
      rag_context = query_rag_for_business_info(info[:business_name])
      if rag_context && rag_context[:content].present?
        info[:rag_context] = rag_context[:content]
        info[:rag_sources] = rag_context[:sources]
        Rails.logger.info "[LandingPageAgent] Added RAG context: #{rag_context[:content][0..200]}..."
      end
      
      # Always ask intelligent questions based on what's missing
      # This ensures we gather the right information for any page type
      questions = determine_missing_fields(info, intent[:page_type])
      
      if questions.any?
          update_status('running', "I need to ask you #{questions.length} questions to create the perfect landing page...", progress: 25)
          
          # Ask each question through Scout
          questions.each_with_index do |question, index|
            info[question[:field]] = request_intelligent_input(question, info, index + 1, questions.length)
          end
        end
      
      # Log what we gathered
      Rails.logger.info "[LandingPageAgent] Gathered info: #{info.keys.join(', ')}"
      Rails.logger.info "[LandingPageAgent] Has RAG context: #{info[:rag_context].present?}"
      Rails.logger.info "[LandingPageAgent] Has style guide: #{info[:style_guide].present?}"
      
      info
    end
    
    def load_entity_data(entity_id)
      entity = Entity.find(entity_id)
      user = entity.users.first
      
      {
        entity_id: entity_id,
        user_id: user&.id,
        name: entity.name,
        subdomain: entity.subdomain,
        business_profile: user&.business_profile&.as_json,
        settings: entity.settings || {},
        primary_color: entity.settings&.dig('primary_color'),
        logo_url: entity.settings&.dig('logo_url'),
        brand_voice: entity.settings&.dig('brand_voice'),
        style_guide: entity.settings&.dig('style_guide')
      }
    end
    
    def determine_missing_fields(info, page_type)
      # Use AI to analyze context and generate intelligent questions
      questions = analyze_and_generate_questions(info, page_type)
      
      # Return the questions instead of just field names
      questions
    end
    
    def analyze_and_generate_questions(info, page_type)
      # Use LLM to analyze context and generate intelligent questions
      system_prompt = <<~PROMPT
        You are an expert landing page strategist helping gather information for a high-converting landing page.
        
        Analyze the available business information and determine what specific questions to ask.
        Consider:
        - The type of landing page (#{page_type})
        - What information is already available
        - The industry and business context
        - What would make the page most compelling and effective
        - Current marketing best practices
        
        Generate 2-4 targeted questions that will get the most impactful information.
        Avoid generic questions. Make them specific and insightful.
        
        For call-to-action questions:
        - Ask naturally: "What would you like visitors to do?"
        - Don't over-explain formatting - we'll handle that
        - Focus on understanding their goal
        
        #{LlmJsonParser::JSON_FORMAT_INSTRUCTIONS}
        
        Example of CORRECT format (note it starts with [ and ends with ]):
        [
          {
            "field": "unique_field_name",
            "question": "The specific question to ask",
            "why": "Brief reason why this information matters",
            "suggestions": ["example answer 1", "example answer 2"] 
          }
        ]
      PROMPT
      
      context_message = <<~MESSAGE
        Creating a #{page_type} landing page for:
        
        Business: #{info[:business_name] || 'Unknown'}
        Industry: #{info[:industry] || 'Not specified'}
        Value Proposition: #{info[:value_proposition] || 'Not defined'}
        Target Audience: #{info[:target_audience] || 'Not specified'}
        Tone: #{info[:tone_of_voice] || 'Professional'}
        
        Already have: #{info.keys.select { |k| info[k].present? }.join(', ')}
        
        What specific information do we need to create a compelling #{humanize_page_type(page_type)} page?
      MESSAGE
      
      begin
        update_status('running', 'Analyzing your business to ask the right questions...', progress: 20)
        
        # Get the user's selected model
        selected_model = @context[:recent_messages]&.last&.dig(:metadata, :model_preference) || 
                        @context[:metadata]&.dig(:model_preference) || 
                        "claude-haiku-4-5-20251001"
        
        bedrock = BedrockService.new
        response = bedrock.send_message(
          system_prompt,
          [{ role: "user", content: context_message }],
          model: selected_model,
          max_tokens: 1500,
          temperature: 0.8,
          json_mode: true
        )
        
        questions = parse_json_from_llm(response, context: 'LandingPageAgent.analyze_questions')
        Rails.logger.info "[LandingPageAgent] Generated #{questions.length} intelligent questions"
        
        questions
      rescue => e
        Rails.logger.error "[LandingPageAgent] Failed to generate questions: #{e.message}"
        
        # Fallback to basic questions
        fallback_questions_for(page_type, info)
      end
    end
    
    def fallback_questions_for(page_type, info)
      questions = []
      
      # Always need a headline if not provided
      unless info[:headline]
        questions << {
          field: :headline,
          question: "What's the main headline that will grab your visitors' attention?",
          why: "The headline is crucial for capturing interest in the first 3 seconds",
          suggestions: ["Transform Your Business with AI", "Get Started in Minutes"]
        }
      end
      
      case page_type
      when :product
        unless info[:product_name]
          questions << {
            field: :product_name,
            question: "What's the name of the product you're showcasing?",
            why: "We need to clearly identify what you're offering",
            suggestions: []
          }
        end
        unless info[:key_benefits]
          questions << {
            field: :key_benefits,
            question: "What are the top 3 benefits your product provides to customers?",
            why: "Benefits sell better than features - we need to show value",
            suggestions: ["Saves time", "Increases revenue", "Reduces costs"]
          }
        end
      when :service  
        unless info[:service_name]
          questions << {
            field: :service_name,
            question: "What service are you offering?",
            why: "Clear service identification helps visitors understand your offer",
            suggestions: []
          }
        end
        unless info[:unique_approach]
          questions << {
            field: :unique_approach,
            question: "What makes your approach different from competitors?",
            why: "Differentiation is key to standing out in the market",
            suggestions: []
          }
        end
      when :general
        unless info[:core_message]
          questions << {
            field: :core_message,
            question: "What's the main message or story you want to tell visitors?",
            why: "A clear message ensures visitors understand your value immediately",
            suggestions: []
          }
        end
      end
      
      # Always ask for CTA if not provided
      unless info[:call_to_action]
        questions << {
          field: :call_to_action,
          question: "What action do you want visitors to take? (e.g., 'Start Free Trial', 'Book a Demo')",
          why: "A clear call-to-action drives conversions",
          suggestions: ["Get Started", "Book a Consultation", "Start Free Trial", "Learn More"]
        }
      end
      
      questions
    end
    
    def request_intelligent_input(question, current_info, question_num, total_questions)
      # Build a conversational prompt with context
      prompt = build_intelligent_prompt(question, current_info, question_num, total_questions)
      
      # Request input from user via Scout (using base class method)
      user_input = request_user_input(
        prompt, 
        options: question[:suggestions].presence
      )
      
      # Process and validate the input
      process_user_input(user_input, question[:field])
    end
    
    def build_intelligent_prompt(question, info, question_num, total_questions)
      prompt = "📋 **Question #{question_num} of #{total_questions}**\n\n"
      prompt += "#{question[:question]}\n\n"
      
      # Add why this matters
      if question[:why]
        prompt += "_Why this matters: #{question[:why]}_\n\n"
      end
      
      # Add suggestions if available
      if question[:suggestions] && question[:suggestions].any?
        prompt += "💡 **Some examples:**\n"
        question[:suggestions].each do |suggestion|
          prompt += "• #{suggestion}\n"
        end
        prompt += "\n"
      end
      
      # Add context-specific hints
      case question[:field]
      when :headline
        prompt += "💭 Think about what would make your #{info[:target_audience] || 'ideal customer'} stop scrolling and pay attention.\n"
      when :call_to_action
        prompt += "💭 Simply tell me what action you want visitors to take - I'll format it perfectly for the button.\n"
        prompt += "💡 Examples: 'book a demo', 'get started', 'contact us', 'sign up for free trial'\n"
      when :key_benefits
        prompt += "💭 Focus on outcomes and transformations, not just features.\n"
      end
      
      prompt
    end
    
    def process_user_input(input, field)
      # Process and clean the input based on field type
      processed_input = case field
      when :key_benefits, :product_features, :benefits
        # Split comma-separated lists
        input.split(/[,\n]/).map(&:strip).reject(&:blank?)
      when :call_to_action
        # Clean up the input but keep it flexible
        cleaned = input.strip
        
        # Only remove very obvious prefixes
        cleaned = cleaned.gsub(/^(let'?s go with|make it say|use)\s+/i, '')
        
        # If it's already short and action-oriented, use as-is
        # Otherwise, let the LLM extract the intent
        if cleaned.split.length <= 4 && cleaned.match?(/\A[A-Z]/)
          cleaned
        else
          # Pass the full input to LLM and let it extract the intent
          input.strip
        end
      when :headline
        # Limit length if needed
        input.strip.truncate(100)
      else
        input.strip
      end
      
      # Validate the processed input
      validate_field_input(field, processed_input)
    end
    
    def request_field_input(field, current_info)
      # Legacy method - redirect to new intelligent system
      question = {
        field: field,
        question: field_prompt(field, current_info),
        why: "This information helps create a more effective landing page",
        suggestions: []
      }
      request_intelligent_input(question, current_info, 1, 1)
    end
    
    def field_prompt(field, info)
      case field
      when :headline
        "What should be the main headline for your landing page?"
      when :product_name
        "What's the name of the product you're featuring?"
      when :product_description
        "Please provide a brief description of your product (2-3 sentences):"
      when :service_name
        "What service are you offering?"
      when :service_benefits
        "What are the main benefits of your service? (List 3-5 benefits)"
      when :offer_description
        "What are you offering to visitors who sign up? (e.g., free guide, consultation, discount)"
      when :call_to_action
        "What action do you want visitors to take? Just tell me naturally - I'll format it for the button"
      when :main_content
        "What's the main message you want to convey on this page?"
      else
        "Please provide information for: #{field.to_s.humanize}"
      end
    end
    
    def validate_field_input(field, input)
      # Basic validation
      return nil if input.blank?
      
      case field
      when :call_to_action
        # Just pass it through - let the LLM handle it
        input
      when :headline
        # Ensure it's not too long
        input.truncate(100)
      else
        input
      end
    end
    
    def create_landing_page(info)
      # Build the landing page
      landing_page = LandingPage.new(
        entity_id: info[:entity_id],
        user_id: info[:user_id] || @context[:user_id],
        title: info[:headline] || info[:product_name] || info[:service_name] || "Welcome",
        slug: generate_slug(info),
        description: info[:value_proposition] || info[:message] || "Welcome to our page",
        status: 'draft',
        metadata: {}
      )
      
      # Build content sections
      content_structure = build_page_content(info)
      landing_page.html_content = convert_to_html(content_structure, info)
      
      # Also store the structured content in metadata for future editing
      landing_page.metadata = landing_page.metadata.merge({
        page_type: info[:page_type].to_s,
        content_structure: content_structure
      })
      
      # Save
      landing_page.save!
      
      update_status('running', 'Landing page created, applying design...', progress: 75)
      
      # Apply styling based on business profile
      apply_page_styling(landing_page, info)
      
      landing_page
    end
    
    def generate_slug(info)
      base = info[:headline] || info[:product_name] || info[:service_name] || "page"
      base_slug = base.parameterize
      
      # Ensure uniqueness by adding a timestamp-based suffix
      timestamp = Time.current.strftime("%Y%m%d-%H%M%S")
      unique_slug = "#{base_slug}-#{timestamp}"
      
      # If still not unique (very unlikely), add a random component
      counter = 0
      while LandingPage.where(entity_id: info[:entity_id], slug: unique_slug).exists?
        counter += 1
        unique_slug = "#{base_slug}-#{timestamp}-#{counter}"
        
        # Safety check to prevent infinite loop
        if counter > 10
          unique_slug = "#{base_slug}-#{SecureRandom.hex(4)}"
          break
        end
      end
      
      unique_slug
    end
    
    def build_page_content(info)
      # Use LLM to generate landing page content
      system_prompt = <<~PROMPT
        You are an elite landing page copywriter and conversion optimization expert. Your landing pages consistently achieve 15%+ conversion rates.
        
        CREATE A HIGH-CONVERTING LANDING PAGE with rich, compelling content following these PROVEN PRINCIPLES:
        
        🎯 CONVERSION PSYCHOLOGY:
        - Hook visitors in the first 3 seconds with a benefit-focused headline
        - Address their #1 pain point immediately
        - Use the PAS framework (Problem-Agitate-Solution)
        - Include social proof to build trust
        - Create urgency without being pushy
        - Remove all friction from the conversion path
        
        ✍️ COPYWRITING RULES:
        - Write like you're talking to ONE person, not a crowd
        - Use "you" and "your" frequently (customer-focused)
        - Every sentence must serve a purpose - no fluff
        - Use power words: Transform, Discover, Unlock, Proven, Guaranteed
        - Write benefits, not features (what's in it for them?)
        - Use specific numbers and results when possible
        - Include emotional triggers that resonate with their desires
        
        📋 REQUIRED STRUCTURE:
        
        1. HERO SECTION:
           - Headline: Clear benefit statement (8-15 words) that makes them think "That's exactly what I want!"
           - Subheadline: Expand on the transformation they'll experience (25-40 words)
           - CTA Button: Action-focused, specific result they'll get
           
        2. CONTENT SECTIONS (Include 4-5 of these):
           
           a) PROBLEM/AGITATION SECTION:
              - Title: Address their current frustration
              - Content: 80-120 words describing their pain points and why they haven't solved them yet
              - Make them think "Yes, that's exactly my situation!"
           
           b) SOLUTION/BENEFITS SECTION:
              - Title: Promise the transformation
              - Content: 80-120 words on how their life/business improves
              - Items: 3-5 specific benefits with brief explanations (20-30 words each)
           
           c) HOW IT WORKS:
              - Title: Show how easy it is
              - Content: 60-80 words overview
              - Items: 3-4 simple steps with descriptions (15-25 words each)
           
           d) SOCIAL PROOF:
              - Title: Build trust with results
              - Content: 40-60 words introducing testimonials
              - Testimonials: 2-3 detailed success stories (40-80 words each)
              - Include specific results/metrics when possible
           
           e) UNIQUE VALUE PROP:
              - Title: Why choose us over alternatives
              - Content: 80-100 words on what makes this special
              - Items: 3-4 differentiators with explanations
           
           f) OVERCOME OBJECTIONS (FAQ):
              - Title: Address their concerns
              - Content: 40-60 words introducing FAQs
              - Items: 3-4 common objections with reassuring answers
        
        3. CLOSING FORM SECTION:
           - Title: Restate the main benefit/transformation
           - Subtitle: Remove friction (e.g., "No credit card required", "Get instant access")
           - Submit button: Specific action + benefit
        
        💡 CONTENT GUIDELINES:
        - Every paragraph should be 3-5 sentences of meaningful content
        - Use concrete examples and scenarios they can visualize
        - Paint a picture of their life AFTER using this solution
        - Include sensory language and emotional outcomes
        - Be specific - vague claims kill conversions
        - If discussing price/value, focus on ROI not cost
        
        🚫 AVOID:
        - Generic corporate speak or jargon
        - "We" focused copy (make it about them)
        - Passive voice
        - Weak words: maybe, possibly, might, could
        - Clichés and overused phrases
        - Making claims without backing them up
        
        Remember: This page has ONE job - get them to take action. Every element should support that goal.
        
        CTA BUTTON INTELLIGENCE:
        When creating the hero.cta_text, intelligently extract the user's intent:
        - Understand conversational input and extract the core action
        - Keep it concise (2-4 words) and action-oriented
        - Common patterns: "Book a Demo", "Get Started", "Sign Up Now", "Learn More", "Contact Us"
        - If the user says something like "I want people to book a demo", make it "Book a Demo"
        - Always use title case for CTA buttons
        
        #{LlmJsonParser::JSON_FORMAT_INSTRUCTIONS}
        
        Return JSON matching this structure exactly (note it starts with { and ends with }):
        {
          "hero": {
            "headline": "Specific benefit-focused headline",
            "subheadline": "Expanded value prop that creates desire and shows transformation",
            "cta_text": "Action + Benefit (e.g., 'Start Saving Time Today')",
            "cta_action": "form"
          },
          "sections": [
            {
              "type": "problem|benefits|how_it_works|social_proof|value_prop|faq",
              "title": "Compelling section headline",
              "content": "REQUIRED: Rich paragraph content - MUST BE minimum 80 words of persuasive, specific copy. Do NOT leave this blank or short!",
              "items": ["Detailed item with 20+ word explanation", "Another specific benefit/feature with details", "Third compelling point fully explained"],
              "testimonials": [{"quote": "Detailed 40+ word success story with specific results and transformation", "author": "Real Name, Title at Company"}]
            }
          ],
          "form": {
            "title": "Final compelling headline restating main benefit",
            "subtitle": "Friction-reducing reassurance (free trial, no CC, instant access, etc)",
            "fields": ["name", "email", "phone"],
            "submit_text": "Get [Specific Benefit] Now"
          }
        }
      PROMPT

      # Fetch entity's style settings and brand guidelines
      entity = Entity.find(@context[:entity_id])
      entity_settings = entity.settings || {}
      
      # Build brand guidelines from gathered info and settings
      brand_guidelines = []
      brand_guidelines << "Primary Color: #{info[:primary_color] || entity_settings['primary_color']}" if info[:primary_color] || entity_settings['primary_color']
      brand_guidelines << "Logo URL: #{info[:logo_url] || entity_settings['logo_url']}" if info[:logo_url] || entity_settings['logo_url']
      brand_guidelines << "Brand Voice: #{info[:brand_voice] || entity_settings['brand_voice']}" if info[:brand_voice] || entity_settings['brand_voice']
      brand_guidelines << "Style Guide: #{info[:style_guide] || entity_settings['style_guide']}" if info[:style_guide] || entity_settings['style_guide']
      
      # Add tone/voice/industry info from gathered data
      if info[:tone_of_voice]
        brand_guidelines << "Tone of Voice: #{info[:tone_of_voice]}"
      end
      
      if info[:industry]
        brand_guidelines << "Industry: #{info[:industry]}"
      end
      
      # Add business profile info if available
      if info[:business_profile]
        profile = info[:business_profile]
        brand_guidelines << "Business Description: #{profile['description']}" if profile['description']
      end
      
      user_message = <<~MESSAGE
        Create a landing page for:
        Business: #{entity.name}
        Page Type: #{info[:page_type]}
        #{info[:product_name] ? "Product: #{info[:product_name]}" : ""}
        #{info[:service_name] ? "Service: #{info[:service_name]}" : ""}
        #{info[:headline] ? "Requested Headline: #{info[:headline]}" : ""}
        #{info[:value_proposition] ? "Value Proposition: #{info[:value_proposition]}" : ""}
        #{info[:message] ? "Main Message: #{info[:message]}" : ""}
        #{info[:target_audience] ? "Target Audience: #{info[:target_audience]}" : ""}
        #{info[:call_to_action] ? "Call to Action Input: #{info[:call_to_action]}" : ""}
        #{info[:key_benefits] ? "Key Benefits:\n#{info[:key_benefits].join("\n- ")}" : ""}
        #{info[:features] ? "Features:\n#{info[:features].join("\n- ")}" : ""}
        
        #{brand_guidelines.any? ? "Brand Guidelines:\n#{brand_guidelines.join("\n")}" : ""}
        
        #{info[:rag_context] ? "\nAdditional Business Context from Knowledge Base:\n#{info[:rag_context][0..1000]}" : ""}
        
        CRITICAL INSTRUCTIONS:
        1. Generate REAL, SPECIFIC content - no placeholders or generic text
        2. Every paragraph must be 80+ words of meaningful, persuasive copy
        3. Use the actual business name and details provided
        4. Include specific benefits and transformations relevant to their industry
        5. If RAG context is provided, incorporate those specific details into the copy
        6. Create compelling copy that would actually convert visitors
        
        CALL-TO-ACTION EXTRACTION:
        If a call-to-action was provided, extract the core action intent:
        - "let's go with book a demo" → "Book a Demo"
        - "I want get started now" → "Get Started Now"
        - "make it say contact us" → "Contact Us"
        The CTA button should be clear, action-oriented, and 2-4 words maximum.
        
        Remember: This is a REAL landing page that will be published. Make it amazing!
      MESSAGE

      # Log what we're sending to the LLM
      Rails.logger.info "[LandingPageAgent] Sending to LLM with brand guidelines: #{brand_guidelines.join(', ')}"
      Rails.logger.info "[LandingPageAgent] Has RAG context: #{info[:rag_context].present? ? 'Yes' : 'No'}"
      Rails.logger.info "[LandingPageAgent] Message preview: #{user_message[0..500]}..."

      begin
        update_status('running', 'Generating page content with AI...', progress: 50)
        
        # Get the user's selected model from context
        selected_model = @context[:recent_messages]&.last&.dig(:metadata, :model_preference) || 
                        @context[:metadata]&.dig(:model_preference) || 
                        "claude-haiku-4-5-20251001"
        
        Rails.logger.info "[LandingPageAgent] Using model: #{selected_model}"
        
        # Initialize BedrockService
        bedrock = BedrockService.new
        
        # Call LLM with JSON mode using user's selected model
        response = bedrock.send_message(
          system_prompt,
          [{ role: "user", content: user_message }],
          model: selected_model,
          max_tokens: 4000,
          temperature: 0.8,
          json_mode: true
        )
        
        # Parse the JSON response
        content = parse_json_from_llm(response, context: 'LandingPageAgent.build_content')
        
        # Log the generated content for debugging
        Rails.logger.info "[LandingPageAgent] Generated content structure:"
        Rails.logger.info "[LandingPageAgent] Hero: #{content[:hero]&.inspect}"
        Rails.logger.info "[LandingPageAgent] Sections count: #{content[:sections]&.length}"
        content[:sections]&.each_with_index do |section, i|
          Rails.logger.info "[LandingPageAgent] Section #{i}: Type: #{section[:type]}, Content length: #{section[:content]&.length}"
        end
        
        # Validate the structure
        unless content[:hero] && content[:sections] && content[:form]
          raise "Invalid content structure from LLM"
        end
        
        update_status('running', 'Content generated successfully', progress: 60)
        content
        
      rescue => e
        Rails.logger.error "[LandingPageAgent] LLM content generation failed: #{e.message}"
        
        # Fallback to basic structure if LLM fails
        {
          hero: {
            headline: info[:headline] || info[:product_name] || info[:service_name] || "Welcome to #{entity.name}",
            subheadline: info[:value_proposition] || info[:message] || "Discover our amazing solutions",
            cta_text: info[:call_to_action] || "Get Started",
            cta_action: "form"
          },
          sections: build_content_sections(info),
          form: {
            title: "Get Started Today",
            fields: ["name", "email", "phone"],
            submit_text: info[:call_to_action] || "Submit"
          }
        }
      end
    end
    
    def convert_to_html(content, info)
      # Use style settings from gathered info
      primary_color = info[:primary_color] || info[:settings]&.dig('primary_color') || '#667eea'
      secondary_color = info[:settings]&.dig('secondary_color') || '#764ba2'
      font_family = info[:settings]&.dig('font_family') || "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif"
      
      # Convert the content structure to HTML with embedded styling
      html = <<~HTML
        <style>
          /* Reset and Base Styles */
          * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
          }
          
          body {
            font-family: #{font_family};
            line-height: 1.6;
            color: #333;
          }
          
          .landing-page {
            min-height: 100vh;
          }
          
          .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 0 20px;
          }
          
          /* Hero Section */
          .hero-section {
            background: linear-gradient(135deg, #{primary_color} 0%, #{secondary_color} 100%);
            color: white;
            padding: 100px 0;
            text-align: center;
          }
          
          .hero-headline {
            font-size: 3rem;
            font-weight: 700;
            margin-bottom: 20px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.1);
          }
          
          .hero-subheadline {
            font-size: 1.25rem;
            margin-bottom: 30px;
            opacity: 0.9;
            max-width: 600px;
            margin-left: auto;
            margin-right: auto;
          }
          
          .cta-button {
            background: white;
            color: #{primary_color};
            border: none;
            padding: 15px 40px;
            font-size: 1.1rem;
            font-weight: 600;
            border-radius: 50px;
            cursor: pointer;
            transition: all 0.3s ease;
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
          }
          
          .cta-button:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(0,0,0,0.3);
          }
          
          /* Content Sections */
          .content-section, .features-section, .benefits-section, .main-section, .problem-section {
            padding: 80px 0;
            background: #f8f9fa;
          }
          
          .content-section:nth-child(even), .main-section:nth-child(even), .problem-section:nth-child(even) {
            background: white;
          }
          
          .content-section h2, .features-section h2, .benefits-section h2, .main-section h2, .problem-section h2 {
            font-size: 2.5rem;
            text-align: center;
            margin-bottom: 20px;
            color: #333;
          }
          
          .content-section p, .main-section p {
            font-size: 1.1rem;
            text-align: center;
            max-width: 800px;
            margin: 0 auto 30px;
            color: #666;
          }
          
          .feature-list {
            list-style: none;
            max-width: 600px;
            margin: 0 auto;
          }
          
          .feature-list li {
            padding: 15px 0 15px 40px;
            position: relative;
            font-size: 1.1rem;
          }
          
          .feature-list li:before {
            content: "✓";
            position: absolute;
            left: 0;
            color: #{primary_color};
            font-size: 1.5rem;
            font-weight: bold;
          }
          
          /* Additional Section Styles */
          .how-it-works-section, .social-proof-section, .value-prop-section, .faq-section {
            padding: 80px 0;
          }
          
          .how-it-works-section:nth-child(odd), .social-proof-section:nth-child(odd), 
          .value-prop-section:nth-child(odd), .faq-section:nth-child(odd) {
            background: #f8f9fa;
          }
          
          .how-it-works-section h2, .social-proof-section h2, .value-prop-section h2, .faq-section h2 {
            font-size: 2.5rem;
            text-align: center;
            margin-bottom: 20px;
            color: #333;
          }
          
          .section-description {
            font-size: 1.2rem;
            text-align: center;
            max-width: 800px;
            margin: 0 auto 50px;
            color: #555;
            line-height: 1.8;
          }
          
          /* How It Works */
          .steps-list {
            max-width: 700px;
            margin: 0 auto;
            counter-reset: step-counter;
          }
          
          .steps-list li {
            padding: 20px 0 20px 60px;
            position: relative;
            font-size: 1.1rem;
            margin-bottom: 30px;
          }
          
          .step-number {
            position: absolute;
            left: 0;
            top: 15px;
            width: 40px;
            height: 40px;
            background: #{primary_color};
            color: white;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: bold;
          }
          
          /* Testimonials */
          .testimonials-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 30px;
            max-width: 1000px;
            margin: 0 auto;
          }
          
          .testimonial {
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
          }
          
          .testimonial blockquote {
            font-style: italic;
            font-size: 1.1rem;
            line-height: 1.6;
            margin: 0 0 15px 0;
            color: #555;
          }
          
          .testimonial cite {
            font-style: normal;
            font-size: 0.9rem;
            color: #888;
            font-weight: 600;
          }
          
          /* Trust Signals */
          .trust-signals {
            display: flex;
            justify-content: center;
            gap: 40px;
            flex-wrap: wrap;
            margin-top: 30px;
          }
          
          .trust-item {
            font-size: 1.1rem;
            color: #666;
            font-weight: 600;
          }
          
          /* Value Points */
          .value-points {
            max-width: 700px;
            margin: 0 auto;
          }
          
          .value-point {
            display: flex;
            align-items: start;
            margin-bottom: 20px;
            font-size: 1.1rem;
            line-height: 1.6;
          }
          
          .checkmark {
            color: #{primary_color};
            font-size: 1.3rem;
            margin-right: 10px;
            flex-shrink: 0;
          }
          
          /* FAQ */
          .faq-items {
            max-width: 800px;
            margin: 0 auto;
          }
          
          .faq-item {
            margin-bottom: 30px;
            padding: 20px;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.05);
          }
          
          .faq-item h4 {
            font-size: 1.2rem;
            margin-bottom: 10px;
            color: #333;
          }
          
          .faq-item p {
            font-size: 1rem;
            color: #666;
            line-height: 1.6;
            margin: 0;
          }
          
          /* Testimonials Section */
          .testimonials-section {
            padding: 80px 0;
            background: white;
          }
          
          /* Form Section */
          .form-section {
            padding: 80px 0;
            background: #f8f9fa;
          }
          
          .form-section h2 {
            text-align: center;
            font-size: 2.5rem;
            margin-bottom: 20px;
          }
          
          .form-subtitle {
            text-align: center;
            font-size: 1.1rem;
            color: #666;
            max-width: 600px;
            margin: 0 auto 40px;
            line-height: 1.6;
          }
          
          .contact-form {
            max-width: 500px;
            margin: 0 auto;
          }
          
          .form-field {
            margin-bottom: 20px;
          }
          
          .form-field label {
            display: block;
            margin-bottom: 5px;
            font-weight: 600;
            color: #333;
          }
          
          .form-field input {
            width: 100%;
            padding: 12px 20px;
            border: 1px solid #ddd;
            border-radius: 25px;
            font-size: 1rem;
            transition: border-color 0.3s ease;
          }
          
          .form-field input:focus {
            outline: none;
            border-color: #{primary_color};
          }
          
          .submit-button {
            width: 100%;
            background: linear-gradient(135deg, #{primary_color} 0%, #{secondary_color} 100%);
            color: white;
            border: none;
            padding: 15px 30px;
            font-size: 1.1rem;
            font-weight: 600;
            border-radius: 50px;
            cursor: pointer;
            transition: all 0.3s ease;
            margin-top: 20px;
          }
          
          .submit-button:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px #{primary_color}66;
          }
          
          /* Responsive */
          @media (max-width: 768px) {
            .hero-headline {
              font-size: 2rem;
            }
            
            .hero-subheadline {
              font-size: 1.1rem;
            }
            
            .content-section h2, .form-section h2 {
              font-size: 2rem;
            }
          }
        </style>
        
        <div class="landing-page">
          <!-- Hero Section -->
          <section class="hero-section">
            <div class="container">
              <h1 class="hero-headline">#{content[:hero][:headline]}</h1>
              <p class="hero-subheadline">#{content[:hero][:subheadline] || ''}</p>
              <button class="cta-button" data-action="#{content[:hero][:cta_action]}">
                #{content[:hero][:cta_text]}
              </button>
            </div>
          </section>
          
          <!-- Content Sections -->
          #{render_sections(content[:sections])}
          
          <!-- Contact Form -->
          <section class="form-section">
            <div class="container">
              <h2>#{content[:form][:title]}</h2>
              #{content[:form][:subtitle] ? "<p class='form-subtitle'>#{content[:form][:subtitle]}</p>" : ""}
              <form class="contact-form">
                #{render_form_fields(content[:form][:fields])}
                <button type="submit" class="submit-button">
                  #{content[:form][:submit_text]}
                </button>
              </form>
            </div>
          </section>
        </div>
      HTML
      
      html
    end
    
    def render_sections(sections)
      sections.map { |section| render_section(section) }.join("\n")
    end
    
    def render_section(section)
      case section[:type]
      when "problem"
        <<~HTML
          <section class="problem-section">
            <div class="container">
              <h2>#{section[:title]}</h2>
              #{section[:content] ? "<p class='section-description'>#{section[:content]}</p>" : ""}
              #{section[:items] ? render_items(section[:items]) : ""}
            </div>
          </section>
        HTML
      when "features", "benefits"
        <<~HTML
          <section class="#{section[:type]}-section">
            <div class="container">
              <h2>#{section[:title]}</h2>
              #{section[:content] ? "<p class='section-description'>#{section[:content]}</p>" : ""}
              #{section[:items] ? render_items(section[:items]) : ""}
            </div>
          </section>
        HTML
      when "how_it_works"
        <<~HTML
          <section class="how-it-works-section">
            <div class="container">
              <h2>#{section[:title]}</h2>
              #{section[:content] ? "<p class='section-description'>#{section[:content]}</p>" : ""}
              #{section[:items] ? render_steps(section[:items]) : ""}
            </div>
          </section>
        HTML
      when "social_proof"
        <<~HTML
          <section class="social-proof-section">
            <div class="container">
              <h2>#{section[:title]}</h2>
              #{section[:content] ? "<p class='section-description'>#{section[:content]}</p>" : ""}
              #{section[:testimonials] ? render_testimonials(section[:testimonials]) : ""}
              #{section[:items] ? render_trust_signals(section[:items]) : ""}
            </div>
          </section>
        HTML
      when "value_prop"
        <<~HTML
          <section class="value-prop-section">
            <div class="container">
              <h2>#{section[:title]}</h2>
              <div class="value-content">
                #{section[:content] ? "<p class='section-description'>#{section[:content]}</p>" : ""}
                #{section[:items] ? render_value_points(section[:items]) : ""}
              </div>
            </div>
          </section>
        HTML
      when "faq"
        <<~HTML
          <section class="faq-section">
            <div class="container">
              <h2>#{section[:title]}</h2>
              #{section[:content] ? "<p class='section-description'>#{section[:content]}</p>" : ""}
              #{section[:items] ? render_faq_items(section[:items]) : ""}
            </div>
          </section>
        HTML
      else
        <<~HTML
          <section class="content-section">
            <div class="container">
              <h2>#{section[:title]}</h2>
              <p class='section-description'>#{section[:content]}</p>
            </div>
          </section>
        HTML
      end
    end
    
    def render_items(items)
      return "" unless items.is_a?(Array)
      
      <<~HTML
        <ul class="feature-list">
          #{items.map { |item| "<li>#{item}</li>" }.join("\n")}
        </ul>
      HTML
    end
    
    def render_steps(items)
      return "" unless items.is_a?(Array)
      
      <<~HTML
        <ol class="steps-list">
          #{items.map.with_index { |item, i| "<li><span class='step-number'>#{i + 1}</span>#{item}</li>" }.join("\n")}
        </ol>
      HTML
    end
    
    def render_testimonials(testimonials)
      return "" unless testimonials.is_a?(Array)
      
      <<~HTML
        <div class="testimonials-grid">
          #{testimonials.map { |t| 
            <<~TESTIMONIAL
              <div class="testimonial">
                <blockquote>"#{t[:quote] || t['quote']}"</blockquote>
                <cite>— #{t[:author] || t['author'] || 'Customer'}</cite>
              </div>
            TESTIMONIAL
          }.join("\n")}
        </div>
      HTML
    end
    
    def render_trust_signals(items)
      return "" unless items.is_a?(Array)
      
      <<~HTML
        <div class="trust-signals">
          #{items.map { |item| "<div class='trust-item'>#{item}</div>" }.join("\n")}
        </div>
      HTML
    end
    
    def render_value_points(items)
      return "" unless items.is_a?(Array)
      
      <<~HTML
        <div class="value-points">
          #{items.map { |item| "<div class='value-point'><span class='checkmark'>✓</span>#{item}</div>" }.join("\n")}
        </div>
      HTML
    end
    
    def render_faq_items(items)
      return "" unless items.is_a?(Array)
      
      <<~HTML
        <div class="faq-items">
          #{items.map { |item| 
            if item.is_a?(Hash)
              <<~FAQ
                <div class="faq-item">
                  <h4>#{item[:question] || item['question'] || item}</h4>
                  <p>#{item[:answer] || item['answer'] || ''}</p>
                </div>
              FAQ
            else
              <<~FAQ
                <div class="faq-item">
                  <p>#{item}</p>
                </div>
              FAQ
            end
          }.join("\n")}
        </div>
      HTML
    end
    
    def render_form_fields(fields)
      fields.map do |field|
        label = field.capitalize
        type = field == "email" ? "email" : "text"
        
        <<~HTML
          <div class="form-field">
            <label for="#{field}">#{label}</label>
            <input type="#{type}" id="#{field}" name="#{field}" required>
          </div>
        HTML
      end.join("\n")
    end
    
    def build_content_sections(info)
      sections = []
      
      # Add appropriate sections based on page type
      case info[:page_type]
      when :product
        sections << {
          type: "features",
          title: "Product Features",
          content: info[:product_description]
        }
      when :service
        sections << {
          type: "benefits",
          title: "Why Choose Us",
          items: parse_benefits(info[:service_benefits])
        }
      when :lead_capture
        sections << {
          type: "offer",
          title: "What You'll Get",
          content: info[:offer_description]
        }
      else
        # General landing page
        sections << {
          type: "main",
          title: "About Us",
          content: info[:message] || "Welcome to #{info[:business_name]}. We're dedicated to providing exceptional solutions that help transform your business and achieve your goals. Our innovative approach and commitment to excellence sets us apart in the industry."
        }
      end
      
      # Add testimonials if available
      sections << {
        type: "testimonials",
        title: "What Our Customers Say",
        items: [] # Would load from database
      }
      
      sections
    end
    
    def parse_benefits(benefits_text)
      return [] unless benefits_text
      
      # Split by newlines or bullets
      benefits_text.split(/[\n•·\-]/).map(&:strip).reject(&:blank?)
    end
    
    def apply_page_styling(landing_page, info)
      # Apply design based on gathered info and settings
      style_settings = {
        primary_color: info[:primary_color] || info[:settings]&.dig('primary_color') || "#667eea",
        secondary_color: info[:settings]&.dig('secondary_color') || "#764ba2",
        font_family: info[:settings]&.dig('font_family') || "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif",
        tone: info[:tone_of_voice] || info[:brand_voice] || "professional",
        logo_url: info[:logo_url]
      }
      
      # Apply any additional brand colors if available
      if info[:settings] && info[:settings]['brand_colors']
        style_settings[:brand_colors] = info[:settings]['brand_colors']
      end
      
      landing_page.update!(
        metadata: landing_page.metadata.merge(style_settings: style_settings)
      )
    end
    
    def finalize_page(landing_page)
      # Publish the page
      landing_page.update!(status: 'published')
      
      # Generate preview URL
      # Assuming the landing page will be available at /l/[subdomain]/[slug]
      entity = Entity.find(landing_page.entity_id)
      preview_url = "/l/#{entity.subdomain}/#{landing_page.slug}"
      
      # Return success info for Scout to communicate
      {
        title: landing_page.title,
        url: preview_url,
        id: landing_page.id,
        status: 'published'
      }
    end
  end
end