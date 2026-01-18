# Amos: The central conversation orchestrator
# Lightweight coordinator that manages state and delegates work

module Amos
  class Orchestrator
    attr_reader :session_id, :user, :entity, :fresh_start_at
    
    def initialize(user, entity, session_id, options = {})
      @user = user
      @entity = entity
      @session_id = session_id
      @fresh_start_at = options[:fresh_start_at]  # Filter memory to only after this time
      @current_space = options[:current_space]  # Track which space user is in (personal, work, design)
      @context = ConversationContext.new(session_id, user, entity, fresh_start_at: @fresh_start_at)
      @job_manager = JobManager.new
      @response_buffer = ResponseBuffer.new
      @active_jobs = {}
      @stream_callback = nil
      @request_host = options[:request_host]  # Store the actual request host
    end
    
    # Set a callback for streaming responses
    def on_stream(&block)
      @stream_callback = block
    end
    
    # Single entry point for ALL messages
    def process_message(content, source: :user, metadata: {})
      Rails.logger.info "[Amos] Processing message from #{source}: #{content[0..100]}..."
      
      # Check if this is a message from an agent (contains agent tags)
      if source == :agent || is_agent_message?(content)
        handle_agent_message(content, metadata)
        return
      end
      
      # NOTE: Agent question answering is now handled ONLY through the question queue UI
      # (/scout/questions/:id/answer). We no longer intercept chat messages to auto-answer
      # agent questions. This allows users to continue chatting with Scout while agent
      # questions are pending in the queue.
      
      # Add to context
      @context.add_message(source, content, metadata)
      
      # Log canvas metadata if present
      if metadata[:canvas]
        Rails.logger.info "[Amos] Canvas metadata passed to context: #{metadata[:canvas].inspect}"
      end
      
      # Determine intent and complexity
      intent = analyze_intent(content)
      
      # ALL queries go through Scout with tools enabled
      # Scout will decide what to do based on the intent
      
      case intent[:approach]
      when :offer_design_space
        # User wants to build something - offer to switch to Design Space first
        offer_design_space(intent)
      when :delegate_to_agent
        # User confirmed or already in design mode - delegate to specialized agent
        delegate_to_agent(intent)
      else
        # Everything else goes through Scout with tools
        # This includes show_canvas, use_tools, conversational, etc.
        handle_with_tools(intent)
      end
    end
    
    # Offer to switch to Design Space for building tasks
    def offer_design_space(intent)
      agent_name = case intent[:suggested_agent]
                   when :platform_factory then "Platform Factory"
                   when :landing_page_agent then "Landing Page Designer"
                   when :email_agent then "Email Architect"
                   else "the Design team"
                   end
      
      response = <<~RESPONSE
        🎨 **Would you like to switch to Design Mode?**
        
        I noticed you want to build something. For the best experience, I recommend switching to the **Design Space** where you'll get:
        
        - 📐 **Visual previews** of what you're building
        - 🧩 **Component gallery** with ready-to-use designs
        - 🔄 **Real-time editing** with live preview
        - 🤖 **#{agent_name}** specialized for this task
        
        **Say "yes" or "let's start"** to switch to Design Mode, or describe what you want and I'll work with you here.
      RESPONSE
      
      broadcast_to_user(response.strip, { complete: true })
      save_assistant_message(response.strip)
    end
    
    # Handle job completion notifications
    def handle_job_completion(job_id, result)
      Rails.logger.info "[Amos] Job #{job_id} completed with result: #{result.inspect}"
      
      job = @active_jobs[job_id]
      return unless job
      
      # Update context with results
      @context.add_job_result(job_id, result)
      
      # Extract content from result (support both :content and :message)
      content = result[:content] || result[:message]
      
      if content
        # Buffer the response
        @response_buffer.add(content, 
          priority: result[:priority] || :normal,
          metadata: { job_id: job_id, agent: job[:agent], result: result }
        )
      end
      
      # Check if this unlocks other jobs
      check_dependencies(job_id)
      
      # Flush appropriate responses to user
      flush_responses
    end
    
    # Query job status
    def query_job_status(job_id = nil)
      if job_id
        @job_manager.status(job_id)
      else
        @active_jobs.map { |id, job| 
          { 
            id: id, 
            agent: job[:agent],
            status: @job_manager.status(id),
            started_at: job[:started_at]
          }
        }
      end
    end
    
    private
    
    def is_agent_message?(content)
      # Check if the message contains agent communication tags
      content.match?(/\[AGENT:\s*[\w_]+\].*\[JOB_ID:\s*[\w-]+\].*\[REQUEST_TYPE:\s*\w+\]/)
    end
    
    def handle_agent_message(content, metadata)
      # Parse agent tags from the message
      agent_match = content.match(/\[AGENT:\s*([\w_]+)\]/)
      job_id_match = content.match(/\[JOB_ID:\s*([\w-]+)\]/)
      status_match = content.match(/\[STATUS:\s*(\w+)\]/)
      request_type_match = content.match(/\[REQUEST_TYPE:\s*(\w+)\]/)
      
      agent_name = agent_match&.[](1)
      job_id = job_id_match&.[](1)
      status = status_match&.[](1)
      request_type = request_type_match&.[](1)
      
      Rails.logger.info "[Amos] Received message from agent: #{agent_name}, job: #{job_id}, type: #{request_type}"
      
      # Save agent messages to database for persistence
      if request_type == 'question'
        # Only save questions that will be shown to the user
        ScoutMessage.create!(
          user_id: @user.id,
          entity_id: @entity&.id,
          session_id: @session_id,
          role: 'assistant',
          content: content,
          metadata: {
            from_agent: true,
            agent_name: agent_name,
            job_id: job_id,
            request_type: request_type
          }
        )
      end
      
      # Handle based on request type
      case request_type
      when 'question'
        # Store the pending input request
        Rails.cache.write("amos_input_request_#{@session_id}", {
          job_id: job_id,
          agent: agent_name,
          timestamp: Time.current
        }, expires_in: 10.minutes)
        
        # Extract the actual question content (remove agent tags)
        question_content = content.gsub(/\[AGENT:.*?\]\[JOB_ID:.*?\]\[STATUS:.*?\]\[REQUEST_TYPE:.*?\]\s*/, '')
        
        # Relay the question directly to the user (no Scout processing)
        clean_response = "To create the perfect landing page, I need to know:\n\n#{question_content}"
        
        # Broadcast the response to the user
        # Don't mark as complete or it will be filtered out
        # The frontend will display it as a standalone message
        broadcast_to_user(clean_response, {})
        
        # Save as assistant message
        save_assistant_message(clean_response)
      when 'update'
        # Status updates can be shown briefly or just logged
        Rails.logger.info "[Amos] Agent #{agent_name} status update: #{content}"
        # Optionally forward to Scout for brief acknowledgment
      when 'completion'
        # Handle completion messages
        handle_job_completion(job_id, { agent: agent_name, message: content })
      else
        # Unknown request type, forward to Scout
        handle_with_tools({ raw_content: content, from_agent: true })
      end
    end
    
    def analyze_intent(content)
      # Simplified approach: Let Scout's LLM decide intelligently
      # Scout has delegation tools and knows when to use them
      # We only intervene for clear delegation needs as a fast path
      
      intent = {
        raw_content: content,
        complexity: :simple,
        suggested_agent: nil,
        approach: :use_tools  # Default to Scout with tools
      }
      
      normalized = content.downcase.strip
      
      # Only check for EXPLICIT delegation needs
      # Let Scout handle everything else (canvas loading, data queries, conversations)
      if needs_specialized_agent_for_creation?(normalized)
        # Check if user is already in Design Space or has confirmed building
        if @current_space == 'design' || user_confirmed_build?(normalized)
          intent[:complexity] = :complex
          intent[:suggested_agent] = suggest_agent(normalized)
          intent[:approach] = :delegate_to_agent
          Rails.logger.info "[Amos] Complex creation task - delegate to: #{intent[:suggested_agent]}"
        else
          # Offer Design Space for building tasks
          intent[:complexity] = :complex
          intent[:approach] = :offer_design_space
          intent[:suggested_agent] = suggest_agent(normalized)
          Rails.logger.info "[Amos] Building task detected - will offer Design Space"
        end
        return intent
      end
      
      # Everything else goes to Scout
      # Scout's LLM will decide whether to:
      # - Load a canvas (show documents, campaigns, etc.)
      # - Use tools to get data
      # - Delegate to specialists (Scout knows how!)
      # - Have a conversation
      # - Or any combination of the above
      Rails.logger.info "[Amos] Sending to Scout with tools - let LLM decide"
      
      intent
    end
    
    def can_answer_directly?(content)
      # Questions that can be answered without tools or data
      direct_answer_patterns = [
        /what\s+is|what's/,
        /how\s+do\s+i/,
        /can\s+you\s+explain/,
        /tell\s+me\s+about/,
        /help\s+with/,
        /guide|tutorial|instructions/
      ]
      
      direct_answer_patterns.any? { |pattern| content.match?(pattern) } &&
        !content.match?(/my|show|list|data|campaigns|contacts|landing\s+pages/)
    end
    
    def can_show_canvas?(content)
      # Check if this is asking to VIEW/SEE data (not create/learn)
      # Must have both viewing intent AND data reference
      
      # Viewing intent patterns
      viewing_patterns = [
        /show\s+me/,
        /let\s+me\s+see/,
        /display/,
        /view/,
        /look\s+at/,
        /list/,
        /\bmy\s+/,  # "my campaigns", "my contacts"
        /tell\s+me\s+about\s+my/,  # "tell me about my campaigns"
        /check/
      ]
      
      # Data that can be shown in canvases
      canvas_data_patterns = [
        /campaigns?/,  # "campaign" or "campaigns"
        /email.*campaign/,
        /campaign.*status/,
        /landing\s+pages?/,  # "landing page" or "landing pages"
        /contacts?|leads?|subscribers?/,
        /task.*monitor|parallel.*task/,
        /integration.*status/,
        /analytic|report|metric/
      ]
      
      # Exclude creation/learning patterns
      exclude_patterns = [
        /create|build|make|generate/,
        /how\s+do\s+i|how\s+to/,
        /what\s+is|what's/,
        /explain|guide|tutorial/
      ]
      
      # Must have viewing intent AND canvas data, but NOT exclude patterns
      has_viewing_intent = viewing_patterns.any? { |p| content.match?(p) }
      has_canvas_data = canvas_data_patterns.any? { |p| content.match?(p) }
      has_exclude = exclude_patterns.any? { |p| content.match?(p) }
      
      # Special case: "my X" always shows canvas if X is viewable data
      if content.match?(/^\s*my\s+/) && has_canvas_data
        return true unless has_exclude
      end
      
      has_viewing_intent && has_canvas_data && !has_exclude
    end
    
    def can_use_tools_for_data?(content)
      # Can Scout use tools to get data?
      # Look for data queries, counts, status checks
      
      data_patterns = [
        /list|count|how\s+many/,
        /status|progress|check/,
        /get|fetch|retrieve|pull/,
        /what\s+(campaigns|contacts|landing|emails|integrations)/,
        /connected|connections/,
        /recent|latest|last\s+\d+/,
        /stripe|payment.*data/
      ]
      
      data_patterns.any? { |pattern| content.match?(pattern) }
    end
    
    def needs_specialized_agent_for_creation?(content)
      # Only delegate EXPLICIT creation/setup tasks
      # Everything else Scout can handle
      
      # FIRST: Check if user wants to OPEN/VIEW something - never delegate these
      open_keywords = ["open", "show", "view", "display", "load", "see", "go to", "take me to"]
      if open_keywords.any? { |keyword| content.include?(keyword) }
        Rails.logger.info "[Amos] User wants to open/view something - not delegating"
        return false
      end
      
      creation_keywords = [
        "create landing page",
        "build landing page", 
        "make landing page",
        "create email campaign",
        "build email campaign",
        "create workflow",
        "import contacts",
        "setup integration",
        "configure integration"
      ]
      
      # Module/custom software creation - only delegate with explicit BUILD/CREATE verbs
      # Don't match just "inventory management" without a creation verb
      module_creation_patterns = [
        /build\s+(a\s+|an\s+)?module/,
        /create\s+(a\s+|an\s+)?module/,
        /design\s+(a\s+|an\s+)?module/,
        /build\s+(a\s+|an\s+)?custom/,
        /create\s+(a\s+|an\s+)?custom/,
        /build\s+me\s+(a\s+|an\s+)?/,
        /help\s+me\s+design/,
        /help\s+me\s+build/,
        /design\s+(a\s+|an\s+)?system/,
        /build\s+(a\s+|an\s+)?inventory/,
        /create\s+(a\s+|an\s+)?inventory/,
        /build\s+(a\s+|an\s+)?tracking/,
        /create\s+(a\s+|an\s+)?tracking/,
        /custom\s+software/,
        /custom\s+app/
      ]
      
      # Check for module/software creation patterns (require creation verb)
      return true if module_creation_patterns.any? { |pattern| content.match?(pattern) }
      
      # Simple check - does the content explicitly ask for creation?
      creation_keywords.any? { |keyword| content.include?(keyword) }
    end
    
    def out_of_scope_needs_agent?(content)
      # Is this out of Scout's scope and needs a specialized agent?
      # Only complex creation/setup tasks
      
      # Landing page creation
      return true if content.match?(/create|build|make|generate/) && content.match?(/landing.*page|website|web.*page/)
      
      # Email campaign creation
      return true if content.match?(/create|build|design|send/) && content.match?(/email|campaign|newsletter/)
      
      # Complex integration setup
      return true if content.match?(/setup|configure|connect/) && content.match?(/stripe|payment|webhook|integration/)
      
      # Data import/export operations
      return true if content.match?(/import|export|migrate/) && content.match?(/contact|lead|data|csv/)
      
      # Complex report generation
      return true if content.match?(/generate|create|build/) && content.match?(/report|analytics|dashboard/)
      
      false
    end
    
    def user_confirmed_build?(content)
      # Check if user explicitly confirmed they want to build something
      # These are strong confirmation phrases that indicate user knows what they want
      confirmation_patterns = [
        /\byes\b/i,
        /\bgo ahead\b/i,
        /\bstart\s+(building|designing|creating)\b/i,
        /\blet'?s\s+(build|design|create|start)\b/i,
        /\bdo it\b/i,
        /\bproceed\b/i,
        /\bget started\b/i,
        /\bbegin\b/i
      ]
      
      confirmation_patterns.any? { |pattern| content.match?(pattern) }
    end
    
    def suggest_agent(content)
      # Map content patterns to specific agents
      # Note: Scout can also use the 'list_available_agents' tool 
      # to dynamically discover agents when needed
      
      case content
      when /module|inventory|tracking|custom software|custom app|build me|design.*system|design it/i
        :platform_factory
      when /landing.*page|website|web.*page/i
        :landing_page_agent
      when /email|campaign|newsletter/i
        :email_agent
      when /stripe|payment|webhook|integration/i
        :integration_agent
      when /import|export|migrate.*data/i
        :data_agent
      when /report|analytics|dashboard/i
        :analytics_agent
      else
        :general_agent
      end
    end
    
    
    def handle_simple_query(intent)
      Rails.logger.info "[Amos] Handling query - using unified Scout mode"
      
      # Everything goes through Scout with tools
      # Scout will decide based on the query what to do
      handle_with_tools(intent)
    end
    
    def handle_show_canvas(intent)
      # For showing canvases, we need to use tools
      # So we force SimpleQueryHandler to use the tools path
      Rails.logger.info "[Amos] Showing canvas for: #{intent[:raw_content]}"
      
      # SimpleQueryHandler will check needs_tools? and use Scout's tools
      # which includes the load_canvas tool
      handle_with_tools(intent)
    end
    
    def handle_direct_answer(intent)
      # Simple conversational response without tools
      handler = SimpleQueryHandler.new(@context)
      
      # Force non-tool handling by prefixing with conversational marker
      query = "Please explain: #{intent[:raw_content]}"
      response = handler.process(query)
      
      if response
        broadcast_to_user(response, { complete: true })
        @context.add_message(:assistant, response, { source: :amos })
      else
        # Fallback to conversational if no response
        handle_conversational(intent)
      end
    end
    
    def handle_with_tools(intent)
      # Use Scout's tools to get data
      handler = SimpleQueryHandler.new(@context)
      
      accumulated_response = ""
      chunk_count = 0
      
      begin
        handler.process_streaming(intent[:raw_content]) do |chunk|
          if chunk.nil?
            Rails.logger.info "[Amos] Nil chunk received, likely delegation occurred"
            next
          end
          
          if chunk.is_a?(Hash) && chunk[:type] == 'canvas_update'
            Rails.logger.info "[Amos] Canvas update from tools: #{chunk[:canvas_type] || chunk[:canvas]}"
            ScoutChannel.broadcast_to(@session_id, {
              type: 'load_canvas',
              canvas: chunk[:canvas_type] || chunk[:canvas],
              canvas_data: chunk[:canvas_data]
            })
          elsif chunk.is_a?(Hash) && chunk[:content]
            text_chunk = chunk[:content].to_s
            chunk_count += 1
            broadcast_to_user(text_chunk, { streaming: true })
            accumulated_response += text_chunk
          elsif chunk.is_a?(String)
            chunk_count += 1
            broadcast_to_user(chunk, { streaming: true })
            accumulated_response += chunk
          end
        end
        
        if accumulated_response && !accumulated_response.empty?
          @context.add_message(:assistant, accumulated_response, { source: :amos })
          
          # Save the assistant message to the database
          save_assistant_message(accumulated_response)
          
          broadcast_to_user(accumulated_response, { complete: true })
        end
      rescue => e
        Rails.logger.error "[Amos] Error in handle_with_tools: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        
        # Send error message to user so UI doesn't freeze
        error_message = "I encountered an issue processing your request. Let me try again with a different approach."
        broadcast_to_user(error_message, { complete: true, error: true })
        
        # Save the error response
        save_assistant_message(error_message)
        
        # Log for model quality tracking
        begin
          ModelQualityLog.create!(
            model_id: @context.current_model || 'unknown',
            event_type: 'streaming_error',
            tool_name: 'handle_with_tools',
            details: e.message.truncate(500),
            entity_id: @context.entity&.id,
            user_id: @context.user&.id,
            session_id: @session_id
          )
        rescue => log_error
          Rails.logger.debug "[Amos] Could not log quality event: #{log_error.message}"
        end
      end
    end
    
    def handle_conversational(intent)
      # Default conversational handling
      handler = SimpleQueryHandler.new(@context)
      
      if handler.can_stream?
        accumulated_response = ""
        handler.process_streaming(intent[:raw_content]) do |chunk|
          text_chunk = chunk.is_a?(String) ? chunk : chunk[:content].to_s
          broadcast_to_user(text_chunk, { streaming: true })
          accumulated_response += text_chunk
        end
        
        if accumulated_response && !accumulated_response.empty?
          @context.add_message(:assistant, accumulated_response, { source: :amos })
          save_assistant_message(accumulated_response)
          broadcast_to_user(accumulated_response, { complete: true })
        end
      else
        response = handler.process(intent[:raw_content])
        @response_buffer.add(response, priority: :immediate)
        flush_responses
      end
    end
    
    def determine_canvas_from_query(query)
      normalized = query.downcase
      
      # Map queries to specific canvases
      case normalized
      when /email.*campaign|campaign|my.*email/
        'email_campaign_viewer'
      when /landing.*page/
        'landing_page_list'
      when /contact|lead|subscriber/
        'contact_list'
      when /task|job.*status|monitor/
        'parallel_tasks'
      when /integration|connection|stripe/
        'integration_status'
      else
        nil
      end
    end
    
    def delegate_to_agent(intent)
      # Enrich task description with attachment info if available
      task_content = intent[:raw_content]
      last_msg = @context.messages.last
      
      if last_msg && last_msg[:metadata][:attached_files].present?
        files_info = last_msg[:metadata][:attached_files].map { |f| 
          "- #{f[:filename]} (URL: #{f[:url]})" 
        }.join("\n")
        task_content += "\n\n[Attached Files]\n#{files_info}\n"
      end

      # Create a job for the specialized agent
      job_spec = {
        agent: intent[:suggested_agent],
        task: task_content,
        context: @context.snapshot,
        session_id: @session_id,
        callback_url: amos_callback_url
      }
      
      job_id = @job_manager.create_job(job_spec)
      
      @active_jobs[job_id] = {
        agent: intent[:suggested_agent],
        started_at: Time.current,
        task: intent[:raw_content]
      }
      
      # Log callback URL for debugging
      Rails.logger.info "[Amos] Creating job for #{intent[:suggested_agent]}"
      Rails.logger.info "[Amos] Request host: #{@request_host}"
      Rails.logger.info "[Amos] Job callback URL: #{job_spec[:callback_url]}"
      
      # Generic acknowledgment from Scout - easy to extend
      agent_name = intent[:suggested_agent].to_s.gsub('_agent', '').gsub('_', ' ').capitalize
      acknowledgment = "I'm working with the #{agent_name} agent to accomplish this. You can continue chatting - check your Work Items inbox (📥) when results are ready."

      # Send acknowledgment message
      ScoutChannel.broadcast_to(@session_id, {
        type: 'assistant_message',
        content: acknowledgment,
        metadata: { from_scout: true }
      }) if defined?(ScoutChannel)

      # Note: No auto canvas load - user stays on current view
      # Results will appear in Work Items inbox

      # Broadcast job creation to task monitor
      ScoutChannel.broadcast_to(@session_id, {
        type: 'task_progress',
        task_id: "amos-#{job_id}",
        task_type: intent[:suggested_agent].to_s,
        agent_type: intent[:suggested_agent].to_s,
        description: intent[:raw_content],
        status: 'queued',
        progress: 0,
        message: 'Starting task...',
        started_at: Time.current.iso8601
      })

      # Log for debugging
      Rails.logger.info "[Amos] Job #{job_id} created for #{intent[:suggested_agent]}"
    end
    
    def check_job_status(intent)
      statuses = query_job_status
      
      if statuses.empty?
        response = "No active tasks at the moment."
      else
        response = "Here's what's happening:\n\n"
        statuses.each do |job|
          response += "• #{job[:agent].to_s.humanize}: #{job[:status][:message]}\n"
        end
      end
      
      @response_buffer.add(response, priority: :immediate)
      flush_responses
    end
    
    def handle_continuation(intent)
      # Get the active workflow/conversation
      active_context = @context.active_workflow
      
      if active_context
        # Route to the appropriate agent
        job_id = active_context[:job_id]
        @job_manager.send_input(job_id, intent[:raw_content])
      else
        @response_buffer.add(
          "I'm not sure what you're referring to. Could you provide more context?",
          priority: :immediate
        )
        flush_responses
      end
    end
    
    def check_dependencies(completed_job_id)
      # Check if any waiting jobs can now proceed
      @active_jobs.each do |job_id, job|
        if job[:waiting_for] == completed_job_id
          @job_manager.resume_job(job_id)
          job.delete(:waiting_for)
        end
      end
    end
    
    def flush_responses
      # Intelligently flush buffered responses
      @response_buffer.flush do |response|
        # Save to database before broadcasting
        if response[:metadata] && !response[:metadata][:streaming]
          save_assistant_message(response[:content])
          @context.add_message(:assistant, response[:content], { source: :amos })
        end
        broadcast_to_user(response[:content], response[:metadata])
      end
    end
    
    def broadcast_to_user(content, metadata = {})
      data = {
        type: 'amos_response',
        content: content,
        metadata: metadata,
        timestamp: Time.current.iso8601
      }
      
      # For streaming chunks, use SSE callback
      if metadata[:streaming] && @stream_callback
        @stream_callback.call(data)
      elsif !metadata[:streaming]
        # For non-streaming messages, use ActionCable only
        begin
          ScoutChannel.broadcast_to(@session_id, data) if defined?(ScoutChannel)
        rescue => e
          Rails.logger.warn "[Amos] ActionCable broadcast failed: #{e.message}"
        end
      end
    end
    
    def save_assistant_message(content)
      # Save the assistant message to the database
      return if content.blank?
      
      begin
        ScoutMessage.create!(
          user_id: @user.id,
          entity_id: @entity&.id,
          session_id: @session_id,
          role: 'assistant',
          content: content,
          metadata: { from_amos: true }
        )
        Rails.logger.info "[Amos] Saved assistant message to database"
      rescue => e
        Rails.logger.error "[Amos] Failed to save assistant message: #{e.message}"
      end
    end
    
    def send_input_to_agent(job_id, input)
      Rails.logger.info "[Amos] Sending input to agent job #{job_id}: #{input}"
      
      # Find the job record and update it with the input
      begin
        job = Amos::JobRecord.find_by(job_id: job_id)
        if job
          # Store the input in the job's input_data
          job.update!(
            input_data: job.input_data.merge('user_input' => input),
            status: 'processing'
          )
          
          # Write to cache for the agent to pick up
          Rails.cache.write("job_input_#{job_id}", { input: input }, expires_in: 10.minutes)
          
          # Broadcast an update to let the agent know input is ready
          ActionCable.server.broadcast(
            "amos_job_#{job_id}",
            {
              type: 'input_received',
              input: input
            }
          )
          
          Rails.logger.info "[Amos] Input sent to agent successfully (cache key: job_input_#{job_id})"
        else
          Rails.logger.error "[Amos] Job not found: #{job_id}"
          broadcast_to_user("I'm sorry, I couldn't find the task that was waiting for your response.")
        end
      rescue => e
        Rails.logger.error "[Amos] Failed to send input to agent: #{e.message}"
        broadcast_to_user("I'm sorry, there was an error sending your response to the agent. Please try again.")
      end
    end
    
    def amos_callback_url
      # Use the request host if provided (includes port), otherwise fall back to defaults
      host = if @request_host
               # In development, strip subdomains from localhost to avoid DNS issues
               if Rails.env.development? && @request_host.include?('.localhost:')
                 # In Docker, use the web service name instead of localhost
                 if ENV['DOCKER_ENV'] || File.exist?('/.dockerenv')
                   'web:3000'
                 else
                   # Extract just localhost:port from something like app.localhost:5001
                   port = @request_host.split(':').last
                   "localhost:#{port}"
                 end
               else
                 @request_host
               end
             elsif defined?(Rails.application.routes.default_url_options)
               options = Rails.application.routes.default_url_options
               # In Docker, use web service name for worker-to-web communication
               if Rails.env.development? && (ENV['DOCKER_ENV'] || File.exist?('/.dockerenv'))
                 'web:3000'
               elsif options[:host] && options[:port]
                 "#{options[:host]}:#{options[:port]}"
               else
                 options[:host] || 'localhost:3000'
               end
             else
               # Default to web:3000 in Docker, localhost:3000 otherwise
               if Rails.env.development? && (ENV['DOCKER_ENV'] || File.exist?('/.dockerenv'))
                 'web:3000'
               else
                 'localhost:3000'
               end
             end
             
      Rails.application.routes.url_helpers.amos_callback_url(
        session_id: @session_id,
        host: host
      )
    end
    
    def current_canvas_is_work_inbox?
      # Check if the current canvas is a task/work viewing canvas
      recent_messages = @context.recent_messages(5)
      recent_messages.any? do |msg|
        metadata = msg[:metadata] || {}
        canvas = metadata[:canvas] || metadata['canvas'] || {}
        canvas_type = canvas[:type] || canvas['type']
        canvas_type.in?(['work_inbox', 'parallel_tasks', 'scheduled_tasks'])
      end
    end
  end
end
