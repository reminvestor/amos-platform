# frozen_string_literal: true

module Tools
  class CreateScheduledTaskTool < BaseTool
    def self.metadata
      {
        name: "create_scheduled_task",
        description: "Create a new scheduled task to run automatically at specified times. Use this when users want to automate recurring work like email summaries, reports, or data syncs. Supports deterministic mode where you can enforce specific tools or agents to be used.",
        category: "scheduling",
        input_schema: {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "A descriptive name for the scheduled task"
            },
            task_type: {
              type: "string",
              enum: %w[email_summary report_generation data_sync email_management research_update custom],
              description: "The type of task: email_summary (summarize emails), report_generation (create reports), data_sync (sync external data), email_management (manage/draft emails), research_update (gather news/updates), custom (other)"
            },
            prompt: {
              type: "string",
              description: "The detailed instruction for what the task should do when it runs"
            },
            schedule_type: {
              type: "string",
              enum: %w[once daily weekly monthly],
              description: "How often to run: once, daily, weekly, or monthly"
            },
            run_at_time: {
              type: "string",
              description: "Time of day to run in HH:MM format (e.g., '09:00' for 9 AM). Required for daily/weekly/monthly."
            },
            run_on_day: {
              type: "integer",
              description: "For weekly: day of week (0=Sunday, 1=Monday, etc.). For monthly: day of month (1-31)."
            },
            timezone: {
              type: "string",
              description: "Timezone for the schedule (e.g., 'America/New_York', 'UTC'). Defaults to user's timezone."
            },
            description: {
              type: "string",
              description: "Optional description of what this task does"
            },
            output_method: {
              type: "string",
              enum: %w[notification email both],
              description: "How to deliver results: notification (in-app), email, or both. Defaults to notification."
            },
            execution_mode: {
              type: "string",
              enum: %w[scout agent_only tool_only],
              description: "Execution mode: 'scout' (default, Scout decides what to use), 'agent_only' (force use of specific agent), 'tool_only' (force use of specific tools). Use agent_only or tool_only for deterministic/predictable output."
            },
            required_agent: {
              type: "string",
              description: "For agent_only mode: the slug of the agent that MUST be used (e.g., 'landing-page-agent', 'research-agent')"
            },
            required_tools: {
              type: "array",
              items: { type: "string" },
              description: "For tool_only mode: list of tools that MUST be used in sequence (e.g., ['web_search', 'create_dynamic_visualization'])"
            },
            allow_fallback: {
              type: "boolean",
              description: "If true (default), falls back to Scout if required agent/tool fails. Set to false for strict deterministic behavior."
            }
          },
          required: %w[name task_type prompt schedule_type]
        }
      }
    end

    def execute(args)
      log_execution(args)

      name = get_arg(args, :name)
      task_type = get_arg(args, :task_type)
      prompt = get_arg(args, :prompt)
      schedule_type = get_arg(args, :schedule_type)
      run_at_time = get_arg(args, :run_at_time)
      run_on_day = get_arg(args, :run_on_day)
      timezone = get_arg(args, :timezone)
      description = get_arg(args, :description)
      output_method = get_arg(args, :output_method, 'notification')
      
      # Deterministic execution options
      execution_mode = get_arg(args, :execution_mode, 'scout')
      required_agent = get_arg(args, :required_agent)
      required_tools = get_arg(args, :required_tools, [])
      allow_fallback = get_arg(args, :allow_fallback, true)

      # Validate required args
      if error = validate_required_args(args, %i[name task_type prompt schedule_type])
        return error
      end
      
      # ==========================================
      # SAFETY: Block scheduled tasks from creating more scheduled tasks
      # ==========================================
      # This prevents runaway loops where a scheduled task execution 
      # accidentally creates more scheduled tasks
      if @context['scheduled_run'] == true || @context['block_new_scheduled_tasks'] == true
        Rails.logger.warn "🚫 [CreateScheduledTask] Blocked: Cannot create scheduled tasks from within a scheduled task execution (user: #{@user&.id})"
        return error_response(
          "Scheduled tasks cannot create new scheduled tasks. This task was blocked to prevent runaway loops. " \
          "If you need to schedule a follow-up task, please do so manually or through a direct user request."
        )
      end

      # Validate schedule requirements
      if schedule_type.in?(%w[daily weekly monthly]) && run_at_time.blank?
        return error_response("run_at_time is required for #{schedule_type} schedules")
      end

      if schedule_type == 'weekly' && run_on_day.nil?
        return error_response("run_on_day (0-6 for day of week) is required for weekly schedules")
      end

      if schedule_type == 'monthly' && run_on_day.nil?
        return error_response("run_on_day (1-31 for day of month) is required for monthly schedules")
      end
      
      # Validate deterministic mode requirements
      if execution_mode == 'agent_only' && required_agent.blank?
        return error_response("required_agent must be specified for agent_only execution mode")
      end
      
      if execution_mode == 'tool_only' && required_tools.blank?
        return error_response("required_tools must be specified for tool_only execution mode")
      end

      begin
        # Parse time
        parsed_time = nil
        if run_at_time.present?
          parsed_time = Time.parse(run_at_time)
        end

        # Get user's timezone if not specified
        # Note: User model may not have timezone attribute, so we default to UTC
        user_timezone = timezone || (@user.respond_to?(:timezone) ? @user&.timezone : nil) || 'UTC'
        
        # ==========================================
        # DEDUPLICATION: Prevent creating duplicate scheduled tasks
        # ==========================================
        # Check if a similar task already exists for this user
        # This prevents runaway loops where scheduled tasks create more scheduled tasks
        
        # Normalize the name for comparison
        normalized_name = name.downcase.gsub(/[^a-z0-9\s]/, '').squeeze(' ').strip
        
        # Extract key words (remove common words)
        stop_words = %w[remind reminder to set up create a an the for my me about please]
        key_words = normalized_name.split.reject { |w| stop_words.include?(w) }.first(5)
        
        # Find potential duplicates by checking existing active tasks
        existing_tasks = ScheduledAgentTask.where(user: @user)
                                           .where(status: %w[active paused])
                                           .limit(200)  # Safety limit
        
        exact_match = existing_tasks.find do |t|
          t_normalized = t.name.downcase.gsub(/[^a-z0-9\s]/, '').squeeze(' ').strip
          t_key_words = t_normalized.split.reject { |w| stop_words.include?(w) }.first(5)
          
          # Check if names are essentially the same
          t_normalized == normalized_name ||
            t_normalized.include?(normalized_name) ||
            normalized_name.include?(t_normalized) ||
            # Check if key words overlap significantly (80%+)
            (key_words.length > 0 && (key_words & t_key_words).length.to_f / key_words.length >= 0.8) ||
            levenshtein_similar?(t_normalized, normalized_name, 0.75)
        end
        
        if exact_match
          Rails.logger.warn "🚫 [CreateScheduledTask] Blocked duplicate task creation for user #{@user.id}: '#{name}' is similar to existing task '#{exact_match.name}' (ID: #{exact_match.id})"
          return success_response(
            task_id: exact_match.id,
            name: exact_match.name,
            task_type: exact_match.task_type,
            schedule: format_schedule(exact_match),
            next_run: exact_match.next_run_at&.strftime('%A, %B %d at %I:%M %p %Z') || 'Not scheduled',
            already_exists: true,
            message: "ℹ️ A similar scheduled task already exists: '#{exact_match.name}'. No new task was created to avoid duplicates."
          )
        end
        
        # Also limit total scheduled tasks per user to prevent abuse
        user_task_count = existing_tasks.count
        if user_task_count >= 100
          Rails.logger.warn "🚫 [CreateScheduledTask] User #{@user.id} has reached the maximum of 100 scheduled tasks"
          return error_response("You have reached the maximum limit of 100 scheduled tasks. Please delete some existing tasks before creating new ones.")
        end
        
        # Build input context with deterministic settings
        input_context = {
          'execution_mode' => execution_mode
        }
        
        if execution_mode == 'agent_only'
          input_context['required_agent_slug'] = required_agent
          input_context['allow_fallback'] = allow_fallback
        elsif execution_mode == 'tool_only'
          input_context['required_tools'] = required_tools
          input_context['allow_fallback'] = allow_fallback
        end

        # Create the scheduled task
        task = ScheduledAgentTask.create!(
          entity: @entity,
          user: @user,
          name: name,
          description: description,
          task_type: task_type,
          prompt: prompt,
          schedule_type: schedule_type,
          run_at_time: parsed_time,
          run_on_day: run_on_day,
          timezone: user_timezone,
          enabled: true,
          status: 'active',
          input_context: input_context,
          output_config: {
            'method' => output_method,
            'email' => @user&.email
          }
        )

        # Format next run for response
        next_run_display = if task.next_run_at
          task.next_run_at.in_time_zone(user_timezone).strftime('%A, %B %d at %I:%M %p %Z')
        else
          'Not scheduled'
        end
        
        # Build execution mode message
        mode_msg = case execution_mode
        when 'agent_only'
          " (🤖 Will use agent: #{required_agent})"
        when 'tool_only'
          " (🔧 Will use tools: #{required_tools.join(', ')})"
        else
          ""
        end

        success_response(
          task_id: task.id,
          name: task.name,
          task_type: task.task_type,
          schedule: format_schedule(task),
          next_run: next_run_display,
          execution_mode: execution_mode,
          deterministic: task.deterministic?,
          message: "✅ Created scheduled task '#{name}'. It will run #{format_schedule(task)}#{mode_msg}. Next run: #{next_run_display}"
        )
      rescue ActiveRecord::RecordInvalid => e
        error_response("Failed to create scheduled task: #{e.message}")
      rescue => e
        Rails.logger.error "Error creating scheduled task: #{e.message}"
        error_response("Failed to create scheduled task: #{e.message}")
      end
    end

    private
    
    # Simple Levenshtein distance-based similarity check
    def levenshtein_similar?(str1, str2, threshold = 0.8)
      return true if str1 == str2
      return false if str1.nil? || str2.nil?
      
      # Quick length check - if lengths differ too much, they're not similar
      len_diff = (str1.length - str2.length).abs
      max_len = [str1.length, str2.length].max
      return false if max_len == 0
      return false if len_diff.to_f / max_len > (1 - threshold)
      
      # Calculate Levenshtein distance
      m, n = str1.length, str2.length
      d = Array.new(m + 1) { Array.new(n + 1, 0) }
      
      (0..m).each { |i| d[i][0] = i }
      (0..n).each { |j| d[0][j] = j }
      
      (1..m).each do |i|
        (1..n).each do |j|
          cost = str1[i - 1] == str2[j - 1] ? 0 : 1
          d[i][j] = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost].min
        end
      end
      
      distance = d[m][n]
      similarity = 1.0 - (distance.to_f / max_len)
      similarity >= threshold
    end

    def format_schedule(task)
      case task.schedule_type
      when 'once'
        'once'
      when 'daily'
        "daily at #{task.run_at_time&.strftime('%I:%M %p')}"
      when 'weekly'
        "weekly on #{Date::DAYNAMES[task.run_on_day || 0]} at #{task.run_at_time&.strftime('%I:%M %p')}"
      when 'monthly'
        "monthly on day #{task.run_on_day} at #{task.run_at_time&.strftime('%I:%M %p')}"
      else
        task.schedule_type
      end
    end
  end
end

