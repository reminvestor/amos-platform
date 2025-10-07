module Agents
  class GatherContextExecutor < PhaseExecutor
    
    def execute
      phase_id = @phase[:id] || @phase['id']
      Rails.logger.info "🔍 GatherContextExecutor: Starting phase #{phase_id}"
      
      notify_progress("Gathering information intelligently...")
      
      # Initialize gathered data
      @gathered_data = {}
      @conversation_turns = 0
      
      # Get context sources in priority order
      context_sources = @phase[:context_sources] || @phase['context_sources']
      sources = if context_sources.is_a?(Hash)
                  context_sources[:priority] || context_sources['priority'] || []
                elsif context_sources.is_a?(Array)
                  context_sources
                else
                  ['workflow_context', 'conversation_history', 'entity_profile', 'direct_conversation']
                end
      
      # Process each source
      sources.each do |source|
        Rails.logger.info "📍 Checking source: #{source}"
        
        case source.to_s
        when 'workflow_context'
          @gathered_data.merge!(check_workflow_context)
        when 'conversation_history'
          @gathered_data.merge!(check_conversation_history)
        when 'entity_profile'
          @gathered_data.merge!(check_entity_profile)
        when 'web_search'
          @gathered_data.merge!(check_web_search)
        when 'direct_conversation'
          # Check conversation for data FIRST
          conversation_data = check_conversation_history
          @gathered_data.merge!(conversation_data)
          
          # Only ask if we STILL need input after checking conversation
          return ask_user_conversationally if needs_user_input?
        end
        
        # Check if we have everything
        break if check_completion_criteria
      end
      
      # Store all gathered data
      store_phase_output(@gathered_data, 'extracted_data')
      
      notify_progress("Information gathered successfully!", type: 'phase_complete')
      
      {
        success: true,
        status: 'completed',
        data: @gathered_data,
        phase: phase_id
      }
    end
    
    private
    
    def check_workflow_context
      Rails.logger.info "🔍 Checking workflow context for existing data..."
      
      gathered = {}
      
      # Get all workflow context
      all_context = get_workflow_context
      
      # Get extraction strategies
      strategies = @phase.dig(:extraction_strategies, :workflow_context) ||
                  @phase.dig('extraction_strategies', 'workflow_context') || {}
      
      file_types = strategies['file_types'] || strategies[:file_types] || {}
      
      # Get uploaded files from context
      file_contexts = @workflow_execution&.workflow_contexts&.files || []
      
      file_contexts.each do |file_context|
        file_info = file_context.as_file_info
        file_type = file_info[:content_type]&.split('/')&.last || 
                   file_info[:filename]&.split('.')&.last
        
        Rails.logger.info "📄 Analyzing file: #{file_info[:filename]} (#{file_type})"
        
        # Extract based on file type
        case file_type.to_s.downcase
        when 'pdf', 'application/pdf'
          extracted = extract_from_pdf(file_info, file_types['pdf'])
          gathered.merge!(extracted) if extracted
        when 'png', 'jpg', 'jpeg', 'image/png', 'image/jpeg'
          extracted = extract_from_image(file_info, file_types['image'])
          gathered.merge!(extracted) if extracted
        when 'docx', 'doc', 'application/msword'
          extracted = extract_from_document(file_info, file_types['docx'])
          gathered.merge!(extracted) if extracted
        end
      end
      
      Rails.logger.info "📦 Extracted from files: #{gathered.keys.join(', ')}"
      gathered
    end
    
    def extract_from_pdf(file_info, extraction_hint)
      # Use AI to extract information from PDF
      prompt = build_extraction_prompt(file_info, extraction_hint, 'PDF')
      
      result = ai_decide(prompt, 
        expect_json: true,
        system_prompt: pdf_extraction_system_prompt
      )
      
      result.is_a?(Hash) ? result : {}
    end
    
    def extract_from_image(file_info, extraction_hint)
      # For images, extract visual info like colors, style
      # Note: This would need vision API integration
      # For now, use filename and metadata
      
      {
        image_provided: true,
        image_url: file_info[:url],
        image_filename: file_info[:filename]
      }
    end
    
    def extract_from_document(file_info, extraction_hint)
      # Similar to PDF extraction
      prompt = build_extraction_prompt(file_info, extraction_hint, 'document')
      
      result = ai_decide(prompt,
        expect_json: true,
        system_prompt: document_extraction_system_prompt
      )
      
      result.is_a?(Hash) ? result : {}
    end
    
    def check_conversation_history
      Rails.logger.info "💬 Checking conversation history..."
      
      gathered = {}
      
      # If we have a direct user message (resume scenario), check it first
      if @context[:user_message].present?
        Rails.logger.info "📨 Checking direct user message first..."
        direct_data = extract_from_message(@context[:user_message])
        gathered.merge!(direct_data) if direct_data.is_a?(Hash)
        
        # Log what we found
        Rails.logger.info "📨 Extracted from direct message: #{gathered.keys.join(', ')}"
        
        # If we got all required fields, return immediately
        return gathered if check_completion_criteria_with_data(gathered)
      end
      
      # Get recent conversation from scout messages
      task_session = @context[:task_session]
      return gathered unless task_session
      
      session_id = task_session.metadata['session_id']
      return gathered unless session_id
      
      messages = ScoutMessage.where(session_id: session_id)
                            .order(created_at: :asc)
                            .limit(20)
                            .select(:role, :content)
      
      return gathered if messages.empty?
      
      # Format conversation for AI
      conversation_text = messages.map { |m| "#{m.role.capitalize}: #{m.content}" }.join("\n\n")
      
      # Get required fields to extract
      required_fields = @phase[:required_fields] || @phase['required_fields'] || []
      fields_list = required_fields.map { |f| "- #{f['key'] || f[:key]}: #{f['prompt'] || f[:prompt]}" }.join("\n")
      
      prompt = <<~PROMPT
        Extract the following information from this conversation if present:
        
        #{fields_list}
        
        Conversation:
        #{conversation_text}
        
        Return ONLY a JSON object with the extracted values. Use null for fields not found.
        Example: {"business_name": "Acme Corp", "target_audience": "small businesses"}
      PROMPT
      
      begin
        result = ai_decide(prompt, expect_json: true, max_tokens: 1000)
        
        if result.is_a?(Hash) && !result.key?('error')
          # Filter out null values and merge with already gathered
          result.each do |key, value|
            gathered[key.to_s] = value if value.present? && !gathered.key?(key.to_s)
          end
          
          Rails.logger.info "💬 Extracted from conversation: #{gathered.keys.join(', ')}"
        end
      rescue => e
        Rails.logger.error "Failed to extract from conversation: #{e.message}"
      end
      
      gathered
    end
    
    def check_entity_profile
      Rails.logger.info "🏢 Checking entity profile..."
      
      gathered = {}
      entity = @context[:entity]
      
      return gathered unless entity
      
      # Map entity fields to required knowledge
      gathered['business_name'] = entity.name if entity.name.present?
      gathered['company_name'] = entity.name if entity.name.present?
      gathered['entity_name'] = entity.name if entity.name.present?
      
      # Add any other entity fields that might be useful
      gathered['subdomain'] = entity.subdomain if entity.subdomain.present?
      
      Rails.logger.info "🏢 Extracted from entity: #{gathered.keys.join(', ')}"
      gathered
    end
    
    def check_web_search
      # Placeholder for web search integration
      # Would search for public info about the business
      {}
    end
    
    def check_completion_criteria
      check_completion_criteria_with_data(@gathered_data)
    end
    
    def check_completion_criteria_with_data(data)
      # Check if we've gathered enough data
      required_fields = @phase[:required_fields] || @phase['required_fields'] || []
      
      # Get truly required fields (not optional)
      truly_required = required_fields.select { |f| f['required'] == true || f[:required] == true }
      
      # If no required fields defined, need at least some basic info
      return data.keys.length >= 3 if truly_required.empty?
      
      # Check which required fields we have
      gathered_keys = data.keys.map(&:to_s)
      missing_required = truly_required.reject do |field|
        field_key = (field['key'] || field[:key]).to_s
        gathered_keys.include?(field_key) || gathered_keys.any? { |k| k.include?(field_key) }
      end
      
      Rails.logger.info "📊 Required: #{truly_required.length}, Gathered: #{gathered_keys.length}, Missing: #{missing_required.length}"
      
      # Only complete if all required fields are gathered
      missing_required.empty?
    end
    
    def extract_from_message(message)
      # Get required fields to extract
      required_fields = @phase[:required_fields] || @phase['required_fields'] || []
      fields_list = required_fields.map { |f| "- #{f['key'] || f[:key]}: #{f['prompt'] || f[:prompt]}" }.join("\n")
      
      prompt = <<~PROMPT
        Extract the following information from this user message if present:
        
        Required Fields:
        #{fields_list}
        
        User Message:
        #{message}
        
        Return ONLY a JSON object with the extracted values. Use null for fields not found.
        Be flexible in your extraction - infer information even if not explicitly stated.
        
        Example: {"company_name": "Acme Corp", "target_audience": "small businesses", "value_proposition": "affordable solutions"}
      PROMPT
      
      begin
        result = ai_decide(prompt, expect_json: true, max_tokens: 1000)
        
        if result.is_a?(Hash) && !result.key?('error')
          # Filter out null values
          extracted = {}
          result.each do |key, value|
            extracted[key.to_s] = value if value.present?
          end
          return extracted
        end
      rescue => e
        Rails.logger.error "Failed to extract from message: #{e.message}"
      end
      
      {}
    end
    
    def needs_user_input?
      # Check if completion criteria is NOT met (meaning we're missing required fields)
      !check_completion_criteria
    end
    
    def find_missing_fields
      required_fields = @phase[:required_fields] || @phase['required_fields'] || []
      missing = []
      
      required_fields.each do |field_def|
        field_key = field_def['key'] || field_def[:key]
        field_prompt = field_def['prompt'] || field_def[:prompt]
        is_required = field_def['required'] || field_def[:required]
        
        # Skip optional fields if we're in the first pass
        next unless is_required
        
        # Check if we have this field
        unless @gathered_data.key?(field_key) || 
               @gathered_data.key?(field_key.to_sym)
          missing << { 
            field: field_key,
            prompt: field_prompt,
            required: is_required
          }
        end
      end
      
      missing
    end
    
    def ask_user_conversationally
      @conversation_turns += 1
      missing = find_missing_fields
      
      Rails.logger.info "💭 Need to ask user for: #{missing.map { |m| m[:field] }.join(', ')}"
      
      # Generate conversational prompt
      prompt = generate_conversational_prompt(missing)
      
      # Send to user via progress callback
      notify_progress(prompt, type: 'content_chunk', awaiting_input: true)
      
      {
        success: true,
        status: 'awaiting_input',
        conversational: true,
        fields_needed: missing.map { |m| m[:field] },
        message: prompt,
        partial_data: @gathered_data
      }
    end
    
    def generate_conversational_prompt(missing_fields)
      # Get AI instructions for conversational prompts
      ai_instructions = @phase[:ai_instructions] || @phase['ai_instructions']
      
      context_summary = @gathered_data.any? ? 
        "Based on what I've found: #{@gathered_data.to_json}" : 
        "I need some information to help you."
      
      # Format missing fields for the AI to understand
      fields_list = missing_fields.map do |m| 
        "- #{m[:field]}: #{m[:prompt]}"
      end.join("\n")
      
      prompt_request = <<~PROMPT
        Generate a natural, friendly conversational prompt to gather this information:
        
        Missing Fields:
        #{fields_list}
        
        Already Gathered: #{@gathered_data.keys.join(', ')}
        
        Guidelines:
        #{ai_instructions}
        
        Generate a single, natural question that asks for the missing information.
        Be friendly and conversational. Group related questions together.
        If you already have some context, acknowledge it and ask for specifics.
        
        Return just the conversational prompt text, no JSON.
      PROMPT
      
      ai_decide(prompt_request, temperature: 0.7) || 
        "I need a bit more information: #{missing_fields.map { |m| m[:field] }.join(', ')}"
    end
    
    def build_extraction_prompt(file_info, extraction_hint, file_type)
      required_knowledge = @phase[:required_knowledge] || @phase['required_knowledge'] || {}
      
      <<~PROMPT
        Extract information from this #{file_type} file for a workflow.
        
        File: #{file_info[:filename]}
        Extraction Hint: #{extraction_hint}
        
        Required Information Categories:
        #{JSON.pretty_generate(required_knowledge)}
        
        Analyze the file and extract any relevant information.
        Return as JSON with field names matching the required information:
        {
          "field_name": "extracted_value"
        }
        
        Only include information you can confidently extract.
        Use clear, simple field names.
      PROMPT
    end
    
    def pdf_extraction_system_prompt
      <<~PROMPT
        You are a document analysis expert. Extract structured information from PDFs.
        
        Focus on:
        - Business information (names, industry, value propositions)
        - Brand guidelines (colors, fonts, messaging)
        - Contact and company details
        - Any structured data tables
        
        Return clean, structured JSON. Be accurate.
      PROMPT
    end
    
    def document_extraction_system_prompt
      <<~PROMPT
        You are a document analysis expert. Extract structured information from documents.
        
        Focus on:
        - Key business information
        - Product/service descriptions
        - Target audience details
        - Goals and objectives
        
        Return clean, structured JSON. Be accurate.
      PROMPT
    end
  end
end
