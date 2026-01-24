# Amos: The central conversation orchestrator
# Amos handles ALL tasks directly using tools - no agent delegation

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
      
      # ═══════════════════════════════════════════════════════════════════════
      # INTENT-BASED MODE DETECTION & ROUTING
      # ═══════════════════════════════════════════════════════════════════════
      # 
      # Amos seamlessly adapts his ROLE based on detected intent mode:
      #   :personal - Relaxed helper for non-work topics
      #   :ideate   - Creative partner for brainstorming (NO actions)
      #   :operate  - Operations orchestrator (execute tasks)
      #   :create   - Creator mode (Amos handles directly with tools)
      #
      # NO delegation to agents. Amos handles EVERYTHING directly with tools.
      #
      
      intent = analyze_intent(content)
      
      # ARCHITECTURE: Amos handles EVERYTHING directly with tools
      # No more delegation to agents - dynamic guidance provides expertise
      # The mode is passed so the system prompt can adapt the role
      handle_with_tools(intent)
    end
    
    # ═══════════════════════════════════════════════════════════════════════════
    # AGENT HANDSHAKE PROTOCOL
    # ═══════════════════════════════════════════════════════════════════════════
    
    def offer_agent_handshake(intent)
      agent_slug = intent[:suggested_agent]
      agent = AgentPlugin.find_by(slug: agent_slug) || AgentPlugin.find_by(slug: agent_slug.to_s.gsub('_agent', ''))
      agent_name = agent&.name || agent_slug.to_s.gsub('_', ' ').titleize
      
      # Store the pending handshake
      store_pending_handshake(intent)
      
      # Build natural language handshake message (works with voice)
      handshake_message = <<~MSG.strip
        I'll assign this to #{agent_name} who specializes in this.
        
        How would you like to proceed?
        
        Say "load now" or "switch to them" to work with #{agent_name} directly in chat - they'll collaborate with you on the details.
        
        Or say "assign it" or "hand it off" to let them work on it. I'll notify you when they have a question or when it's complete.
      MSG
      
      # Send the handshake offer
      ScoutChannel.broadcast_to(@session_id, {
        type: 'assistant_message',
        content: handshake_message,
        metadata: { 
          from_scout: true,
          handshake_pending: true,
          suggested_agent: agent_slug,
          agent_name: agent_name
        }
      }) if defined?(ScoutChannel)
      
      Rails.logger.info "[Amos] Offered handshake for #{agent_name} (#{agent_slug})"
    end
    
    def store_pending_handshake(intent)
      cache_key = "pending_handshake:#{@session_id}"
      Rails.cache.write(cache_key, {
        raw_content: intent[:raw_content],
        suggested_agent: intent[:suggested_agent],
        mode: intent[:mode],
        stored_at: Time.current.iso8601
      }, expires_in: 10.minutes)
    end
    
    def retrieve_pending_handshake
      cache_key = "pending_handshake:#{@session_id}"
      Rails.cache.read(cache_key)
    end
    
    def clear_pending_handshake
      cache_key = "pending_handshake:#{@session_id}"
      Rails.cache.delete(cache_key)
    end
    
    def check_for_handshake_response(content)
      pending = retrieve_pending_handshake
      return nil unless pending
      
      normalized = content.downcase.strip
      
      # Check for "load now" / "switch to them" patterns
      load_now_patterns = [
        /\bload\s*(them|it|now|agent)?\b/i,
        /\bswitch\s*(to\s*them|to\s*\w+|now)?\b/i,
        /\bwork\s*with\s*(them|directly)/i,
        /\blet\s*me\s*(talk|work|chat)\s*(to|with)\s*(them|directly)/i,
        /\bopen\s*(the\s*)?agent/i,
        /\bdirect(ly)?\b/i,
        /\bcollaborate\b/i
      ]
      
      # Check for "assign & continue" patterns
      assign_patterns = [
        /\bassign\s*(it|them|task)?\b/i,
        /\bhand\s*(it\s*)?(off|over)\b/i,
        /\blet\s*(them|it)\s*(work|handle|run)/i,
        /\bstart\s*(the\s*)?(process|task|work)/i,
        /\bqueue\s*(it)?\b/i,
        /\bbackground\b/i,
        /\bcome\s*back\s*(to\s*it\s*)?later/i,
        /\bnotify\s*(me|when)/i,
        /\bjust\s*(do|start)\s*(it)?\b/i
      ]
      
      if load_now_patterns.any? { |p| normalized.match?(p) }
        { action: :load_now, pending: pending }
      elsif assign_patterns.any? { |p| normalized.match?(p) }
        { action: :assign_and_continue, pending: pending }
      else
        nil  # Not a handshake response, treat as new message
      end
    end
    
    def handle_handshake_response(response, original_content)
      pending = response[:pending]
      agent_slug = pending[:suggested_agent]
      agent = AgentPlugin.find_by(slug: agent_slug) || AgentPlugin.find_by(slug: agent_slug.to_s.gsub('_agent', ''))
      agent_name = agent&.name || agent_slug.to_s.gsub('_', ' ').titleize
      
      clear_pending_handshake
      
      case response[:action]
      when :load_now
        handle_load_now(pending, agent, agent_name)
      when :assign_and_continue
        handle_assign_and_continue(pending, agent, agent_name)
      end
    end
    
    def handle_load_now(pending, agent, agent_name)
      Rails.logger.info "[Amos] User chose LOAD NOW for #{agent_name}"
      
      # Create the task but also switch the active agent in chat
      intent = {
        raw_content: pending[:raw_content],
        suggested_agent: pending[:suggested_agent],
        mode: pending[:mode]
      }
      
      # Delegate the task
      delegate_to_agent_with_load(intent, agent)
      
      # Send confirmation
      message = "Connecting you with #{agent_name} now. They have the context from our conversation and will work with you directly."
      
      ScoutChannel.broadcast_to(@session_id, {
        type: 'assistant_message',
        content: message,
        metadata: { 
          from_scout: true,
          agent_loaded: true,
          agent_slug: agent&.slug,
          agent_name: agent_name
        }
      }) if defined?(ScoutChannel)
      
      # Signal the frontend to switch to agent chat
      ScoutChannel.broadcast_to(@session_id, {
        type: 'switch_to_agent',
        agent_slug: agent&.slug,
        agent_name: agent_name,
        agent_id: agent&.id,
        task_context: pending[:raw_content]
      }) if defined?(ScoutChannel)
    end
    
    def handle_assign_and_continue(pending, agent, agent_name)
      Rails.logger.info "[Amos] User chose ASSIGN & CONTINUE for #{agent_name}"
      
      intent = {
        raw_content: pending[:raw_content],
        suggested_agent: pending[:suggested_agent],
        mode: pending[:mode]
      }
      
      # Delegate the task (agent works in background)
      delegate_to_agent(intent)
      
      # Send confirmation
      message = "Got it! I've assigned this to #{agent_name}. They'll use their judgment - if they need your input, I'll let you know. You can check their progress in the pending tasks area."
      
      ScoutChannel.broadcast_to(@session_id, {
        type: 'assistant_message',
        content: message,
        metadata: { 
          from_scout: true,
          task_assigned: true,
          agent_slug: agent&.slug,
          agent_name: agent_name
        }
      }) if defined?(ScoutChannel)
    end
    
    def delegate_to_agent_with_load(intent, agent)
      # Similar to delegate_to_agent but marks as "active" in chat
      task_content = intent[:raw_content]
      last_msg = @context.messages.last
      
      if last_msg && last_msg[:metadata][:attached_files].present?
        files_info = last_msg[:metadata][:attached_files].map { |f| 
          "- #{f[:filename]} (URL: #{f[:url]})" 
        }.join("\n")
        task_content += "\n\n[Attached Files]\n#{files_info}\n"
      end

      job_spec = {
        agent: intent[:suggested_agent],
        task: task_content,
        context: @context.snapshot,
        session_id: @session_id,
        callback_url: amos_callback_url,
        active_in_chat: true  # Flag that agent is now the active chat participant
      }
      
      job_id = @job_manager.create_job(job_spec)
      
      @active_jobs[job_id] = {
        agent: intent[:suggested_agent],
        started_at: Time.current,
        task: intent[:raw_content],
        active_in_chat: true
      }
      
      # Broadcast job creation with active status
      ScoutChannel.broadcast_to(@session_id, {
        type: 'task_progress',
        task_id: "amos-#{job_id}",
        task_type: intent[:suggested_agent].to_s,
        agent_type: intent[:suggested_agent].to_s,
        description: intent[:raw_content],
        status: 'active',
        progress: 0,
        message: "Working with #{agent&.name || 'agent'}...",
        started_at: Time.current.iso8601,
        active_in_chat: true
      })
      
      Rails.logger.info "[Amos] Job #{job_id} created for #{intent[:suggested_agent]} (ACTIVE IN CHAT)"
    end
    
    def check_for_pending_confirmation(content)
      # Check if user is confirming a pending build request
      confirmation_patterns = [
        /\byes\b/i,
        /\bgo ahead\b/i,
        /\blet'?s\s+(start|do it|build|design|go)\b/i,
        /\bdo it\b/i,
        /\bproceed\b/i,
        /\bsure\b/i,
        /\bok\b/i,
        /\byep\b/i,
        /\byeah\b/i,
        /\bswitch\s+to\s+design/i,
        /\bdesign\s+mode\b/i
      ]
      
      if confirmation_patterns.any? { |pattern| content.match?(pattern) }
        pending = retrieve_pending_build_request
        return pending if pending
      end
      
      nil
    end
    
    # DEPRECATED: No longer used - we now delegate immediately without asking
    # Kept for backward compatibility but should not be called
    # The new intent-based system (Phase 1-3) handles creation requests seamlessly
    def offer_design_space(intent)
      Rails.logger.warn "[Amos] DEPRECATED: offer_design_space called - should use direct delegation"
      # Just delegate immediately instead of asking
      delegate_to_agent(intent)
    end
    
    def store_pending_build_request(intent)
      # Store in Rails cache with the session ID so we can retrieve it when user confirms
      cache_key = "pending_build_request:#{@session_id}"
      Rails.cache.write(cache_key, {
        raw_content: intent[:raw_content],
        suggested_agent: intent[:suggested_agent],
        stored_at: Time.current.iso8601
      }, expires_in: 30.minutes)
      Rails.logger.info "[Amos] Stored pending build request for session #{@session_id}: #{intent[:raw_content][0..50]}..."
    end
    
    def retrieve_pending_build_request
      cache_key = "pending_build_request:#{@session_id}"
      request = Rails.cache.read(cache_key)
      Rails.cache.delete(cache_key) if request  # Clear after retrieval
      request
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
      # ═══════════════════════════════════════════════════════════════════════
      # INTENT-BASED MODE DETECTION (Phases 1-3 of seamless mode adaptation)
      # ═══════════════════════════════════════════════════════════════════════
      #
      # Four modes - Amos's identity stays constant, only the ROLE adapts:
      #   :personal - Non-work topics, casual conversation, life admin
      #   :ideate   - Brainstorming, exploring ideas (NO actions, just discuss)
      #   :operate  - Business operations, data queries, task execution
      #   :create   - Building something - delegate to specialist agents
      #
      # Transitions are SEAMLESS - no announcements, no mode switching prompts.
      #
      
      intent = {
        raw_content: content,
        complexity: :simple,
        suggested_agent: nil,
        approach: :use_tools,  # Default
        mode: :operate         # Default mode
      }
      
      # Use IntentClassifierService for mode detection (fast regex + LLM fallback)
      begin
        classifier = IntentClassifierService.new(entity: @entity)
        mode_result = classifier.classify_mode(message: content)
        
        intent[:mode] = mode_result[:mode]
        intent[:mode_confidence] = mode_result[:confidence]
        intent[:create_target] = mode_result[:create_target] if mode_result[:create_target]
        
        Rails.logger.info "[Amos] Mode detected: #{intent[:mode]} (confidence: #{intent[:mode_confidence]})"
      rescue => e
        Rails.logger.warn "[Amos] Mode classification failed: #{e.message}"
        intent[:mode] = :operate
        intent[:mode_confidence] = :low
      end
      
      # Route based on detected mode
      case intent[:mode]
      when :personal
        # Personal mode - use tools but with relaxed personal context
        intent[:approach] = :use_tools
        Rails.logger.info "[Amos] Personal mode - relaxed helper role"
        
      when :ideate
        # Ideate mode - brainstorming, NO actions (tool calls disabled in prompt)
        intent[:approach] = :use_tools
        Rails.logger.info "[Amos] Ideate mode - creative partner, no actions"
        
      when :create
        # Create mode - Amos handles directly with tools
        # Dynamic guidance will inject task-specific expertise
        intent[:complexity] = :complex
        intent[:approach] = :use_tools
        Rails.logger.info "[Amos] Create mode - handling directly with tools (target: #{intent[:create_target]})"
        
      when :operate
        # Operate mode - default, execute with tools
        intent[:approach] = :use_tools
        Rails.logger.info "[Amos] Operate mode - orchestrator role"
      end
      
      intent
    end
    
    # Suggest the best agent based on what the user wants to create
    def suggest_agent_for_creation(create_target, content)
      case create_target
      when :landing_page
        :landing_page_manager
      when :email
        :email_sequence_architect
      when :workflow
        :workflow_architect
      when :module, :app
        :application_planner
      when :integration
        :integration_architect
      when :agent
        :agent_architect
      else
        # Fallback to content-based suggestion
        suggest_agent(content)
      end
    end
    
    # DEPRECATED: route_to_design_space - Amos handles everything directly now
    def route_to_design_space(intent, normalized, source)
      # Amos handles all creation tasks directly with tools
      intent[:complexity] = :complex
      intent[:approach] = :use_tools
      Rails.logger.info "[Amos] Create mode - handling directly with tools (via #{source})"
      intent
    end
    
    # Quick check: might this be a design request? (triggers LLM fallback)
    def might_be_design_request?(content)
      # Don't bother LLM for clear non-creation requests
      return false if content.match?(/show|list|view|display|open|check|status|how\s+many|what\s+are/)
      
      # Potential creation keywords that warrant LLM classification
      potential_creation_patterns = [
        /\b(need|want|like)\s+(a\s+|an\s+)?[\w\s]*(way|system|tool|tracker|solution)/i,
        /\b(help|can\s+you)\b.*\b(track|manage|organize|automate)/i,
        /\b(set\s*up|make|have)\b.*\b(something|system|app|module|page)/i,
        /\b(i|we)\s+(need|want)\b/i
      ]
      
      potential_creation_patterns.any? { |p| content.match?(p) }
    end
    
    # Call IntentClassifierService for design intent (quick LLM call)
    def classify_design_intent_via_llm(content)
      return nil unless @entity.present?
      
      begin
        classifier = IntentClassifierService.new(entity: @entity)
        result = classifier.classify(
          message: content,
          conversation_history: [],  # Could add history for better context
          needs: [:design_intent]    # Only need design intent - minimal call
        )
        result[:design_intent]
      rescue => e
        Rails.logger.warn "[Amos] Design intent LLM classification failed: #{e.message}"
        nil
      end
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
      
      # Module/custom software creation - delegate with explicit BUILD/CREATE verbs
      # Match patterns like "create a project management module"
      module_creation_patterns = [
        /build\s+(a\s+|an\s+)?[\w\s]*\bmodule\b/,     # "build a project management module"
        /create\s+(a\s+|an\s+)?[\w\s]*\bmodule\b/,    # "create a crm module"
        /design\s+(a\s+|an\s+)?[\w\s]*\bmodule\b/,    # "design a tracking module"
        /build\s+(a\s+|an\s+)?[\w\s]*\bapp\b/,        # "build a task app"
        /create\s+(a\s+|an\s+)?[\w\s]*\bapp\b/,       # "create an inventory app"
        /build\s+(a\s+|an\s+)?custom/,                 # "build a custom..."
        /create\s+(a\s+|an\s+)?custom/,                # "create a custom..."
        /build\s+me\s+(a\s+|an\s+)?/,                  # "build me a..."
        /help\s+me\s+(design|build|create)/,           # "help me design..."
        /design\s+(a\s+|an\s+)?[\w\s]*\bsystem\b/,    # "design a tracking system"
        /build\s+(a\s+|an\s+)?[\w\s]*\bsystem\b/,     # "build an inventory system"
        /create\s+(a\s+|an\s+)?[\w\s]*\bsystem\b/,    # "create a crm system"
        /i\s+(need|want)\s+(a\s+|an\s+)?[\w\s]*\bmodule\b/,  # "I need a crm module"
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
    
    def switch_to_design_space
      # Update user's active space to Design using the proper method
      @user.switch_space('design') if @user.respond_to?(:switch_space)
      @current_space = 'design'
      
      # Notify frontend to switch the UI
      ScoutChannel.broadcast_to(@session_id, {
        type: 'switch_space',
        space: 'design',
        message: '🎨 Switching to Design Space...'
      }) if defined?(ScoutChannel)
      
      Rails.logger.info "[Amos] Switched user to Design Space"
    end
    
    def suggest_agent(content, llm_design_intent: nil)
      # Map content patterns (or LLM-detected intent) to specific agents
      # Note: Scout can also use the 'list_available_agents' tool 
      # to dynamically discover agents when needed
      
      # Use LLM design intent if available (more reliable)
      if llm_design_intent.present?
        case llm_design_intent.to_sym
        when :module, :app
          return :module_architect
        when :landing_page
          return :landing_page_manager
        when :email
          return :email_sequence_architect
        when :workflow
          return :module_architect  # Workflows are part of modules
        when :integration
          return :integration_architect
        when :agent
          return :agent_architect
        end
      end
      
      # Fallback to regex-based agent suggestion
      case content
      when /\bmodule\b|inventory|tracking|custom software|custom app|build me|design.*system|design it/i
        :module_architect  # Module Architect for designing new data models/modules
      when /landing.*page|website|web.*page/i
        :landing_page_manager
      when /email|campaign|newsletter/i
        :email_sequence_architect
      when /stripe|payment|webhook|integration/i
        :integration_architect
      when /import|export|migrate.*data/i
        :data_agent
      when /report|analytics|dashboard/i
        :analytics_agent
      else
        :module_architect  # Default to module architect for general design tasks
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
      handler.intent_mode = intent[:mode]  # Pass intent mode for role adaptation
      
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
      # Pass intent mode for seamless role adaptation
      handler = SimpleQueryHandler.new(@context)
      handler.intent_mode = intent[:mode]  # :personal, :ideate, :operate, :create
      
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
