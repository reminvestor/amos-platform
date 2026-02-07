# frozen_string_literal: true

module Tools
  class ManageScheduledTaskTool < BaseTool
    def self.metadata
      {
        name: "manage_scheduled_task",
        description: "Manage an existing scheduled task - pause, resume, run now, update, delete, or reset failures.",
        category: "scheduling",
        input_schema: {
          type: "object",
          properties: {
            task_id: {
              type: "integer",
              description: "The ID of the scheduled task to manage"
            },
            task_name: {
              type: "string",
              description: "The name of the scheduled task (alternative to task_id)"
            },
            action: {
              type: "string",
              enum: %w[pause resume run_now delete update reset_failures],
              description: "The action to perform: pause, resume, run_now (execute immediately), delete, update, or reset_failures (clear failure counter)"
            },
            updates: {
              type: "object",
              description: "For 'update' action: fields to update",
              properties: {
                name: { type: "string", description: "Task name" },
                description: { type: "string", description: "Task description" },
                task_type: { type: "string", enum: %w[email_summary report_generation data_sync custom email_management research_update], description: "Type of task" },
                prompt: { type: "string", description: "Task instructions/prompt" },
                schedule_type: { type: "string", enum: %w[once daily weekly monthly], description: "Schedule frequency" },
                run_at_time: { type: "string", description: "Time to run (HH:MM format)" },
                run_on_day: { type: "integer", description: "Day to run (0-6 for weekly, 1-31 for monthly)" },
                timezone: { type: "string", description: "Timezone for schedule" },
                enabled: { type: "boolean", description: "Whether task is enabled" },
                execution_mode: { type: "string", enum: %w[scout agent_only tool_only], description: "Execution mode: scout (AI decides), agent_only, or tool_only" },
                required_tools: { type: "array", items: { type: "string" }, description: "For tool_only mode: list of tools to use" },
                required_agent_slug: { type: "string", description: "For agent_only mode: agent slug to use" },
                allow_fallback: { type: "boolean", description: "Allow fallback to Scout if agent/tool fails" },
                output_method: { type: "string", enum: %w[notification email both], description: "How to deliver results" }
              }
            }
          },
          required: ["action"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      task_id = get_arg(args, :task_id)
      task_name = get_arg(args, :task_name)
      action = get_arg(args, :action)
      updates = get_arg(args, :updates, {})

      if task_id.blank? && task_name.blank?
        return error_response("Either task_id or task_name is required")
      end

      if action.blank?
        return error_response("action is required")
      end

      begin
        # Find the task
        task = if task_id.present?
          ScheduledAgentTask.find_by(
            id: task_id,
            entity: @entity,
            user: @user
          )
        else
          # Try exact match first, then case-insensitive, then partial match
          ScheduledAgentTask.find_by(
            name: task_name,
            entity: @entity,
            user: @user
          ) || ScheduledAgentTask.where(entity: @entity, user: @user)
                                 .where("LOWER(name) = LOWER(?)", task_name.to_s)
                                 .first ||
             ScheduledAgentTask.where(entity: @entity, user: @user)
                               .where("LOWER(name) LIKE LOWER(?)", "%#{task_name}%")
                               .first
        end

        unless task
          # Provide helpful error with list of existing tasks
          existing_tasks = ScheduledAgentTask.where(entity: @entity, user: @user)
                                             .order(created_at: :desc)
                                             .limit(10)
                                             .map { |t| { id: t.id, name: t.name, type: t.task_type, status: t.status } }

          if existing_tasks.any?
            return error_response(
              "Scheduled task '#{task_name || task_id}' not found.",
              existing_tasks: existing_tasks,
              hint: "Use one of these task names or IDs to manage them."
            )
          else
            return error_response("No scheduled tasks found. Create one first with create_scheduled_task.")
          end
        end

        case action
        when 'pause'
          perform_pause(task)
        when 'resume'
          perform_resume(task)
        when 'run_now'
          perform_run_now(task)
        when 'delete'
          perform_delete(task)
        when 'update'
          perform_update(task, updates)
        when 'reset_failures'
          perform_reset_failures(task)
        else
          error_response("Unknown action: #{action}")
        end
      rescue => e
        Rails.logger.error "Error managing scheduled task: #{e.message}"
        error_response("Failed to manage scheduled task: #{e.message}")
      end
    end

    private

    def perform_pause(task)
      if task.status == 'paused'
        return success_response(
          task_id: task.id,
          name: task.name,
          task_type: task.task_type,
          status: task.status,
          message: "Task '#{task.name}' is already paused."
        )
      end

      task.pause!
      success_response(
        task_id: task.id,
        name: task.name,
        task_type: task.task_type,
        status: task.status,
        message: "⏸️ Paused scheduled task '#{task.name}'. It will not run until resumed."
      )
    end

    def perform_resume(task)
      if task.status == 'active'
        return success_response(
          task_id: task.id,
          name: task.name,
          task_type: task.task_type,
          status: task.status,
          next_run: task.next_run_at&.strftime('%b %d at %I:%M %p'),
          message: "Task '#{task.name}' is already active."
        )
      end

      task.resume!
      success_response(
        task_id: task.id,
        name: task.name,
        task_type: task.task_type,
        status: task.status,
        next_run: task.next_run_at&.strftime('%b %d at %I:%M %p'),
        message: "▶️ Resumed scheduled task '#{task.name}'. Next run: #{task.next_run_at&.strftime('%b %d at %I:%M %p')}"
      )
    end

    def perform_run_now(task)
      unless task.can_run?
        return error_response("Cannot run task '#{task.name}'. Status: #{task.status}, Enabled: #{task.enabled?}")
      end

      # Queue the execution
      ExecuteScheduledAgentTaskJob.perform_later(task.id)

      success_response(
        task_id: task.id,
        name: task.name,
        message: "⚡ Queued immediate execution of '#{task.name}'. Results will be available shortly."
      )
    end

    def perform_delete(task)
      name = task.name
      task.destroy!

      success_response(
        deleted: true,
        name: name,
        message: "🗑️ Deleted scheduled task '#{name}'."
      )
    end

    def perform_update(task, updates)
      if updates.blank?
        return error_response("No updates provided. Specify fields to update in the 'updates' parameter.")
      end

      # Direct model fields
      direct_fields = %i[name description task_type prompt schedule_type run_on_day timezone enabled]
      # Fields that go into input_context
      context_fields = %i[execution_mode required_tools required_agent_slug allow_fallback]
      # Fields that go into output_config
      output_fields = %i[output_method]
      
      filtered_updates = {}
      context_updates = {}
      output_updates = {}
      updated_field_names = []

      updates.each do |key, value|
        key_sym = key.to_sym
        
        if direct_fields.include?(key_sym)
          filtered_updates[key_sym] = value
          updated_field_names << key_sym
        elsif key_sym == :run_at_time && value.present?
          filtered_updates[key_sym] = Time.parse(value) rescue value
          updated_field_names << key_sym
        elsif context_fields.include?(key_sym)
          context_updates[key_sym.to_s] = value
          updated_field_names << key_sym
        elsif output_fields.include?(key_sym)
          output_updates['method'] = value if key_sym == :output_method
          updated_field_names << key_sym
        end
      end

      if updated_field_names.empty?
        return error_response("No valid updates provided.")
      end

      # Apply direct updates
      task.assign_attributes(filtered_updates) if filtered_updates.any?
      
      # Merge input_context updates
      if context_updates.any?
        current_context = task.input_context || {}
        
        # Handle required_tools - ensure it's an array
        if context_updates['required_tools'].is_a?(String)
          context_updates['required_tools'] = context_updates['required_tools'].split(',').map(&:strip).reject(&:blank?)
        end
        
        task.input_context = current_context.merge(context_updates)
      end
      
      # Merge output_config updates
      if output_updates.any?
        current_output = task.output_config || {}
        task.output_config = current_output.merge(output_updates)
      end
      
      task.save!

      success_response(
        task_id: task.id,
        name: task.name,
        updated_fields: updated_field_names,
        execution_mode: task.execution_mode,
        next_run: task.next_run_at&.strftime('%b %d at %I:%M %p'),
        message: "✏️ Updated scheduled task '#{task.name}'. Fields changed: #{updated_field_names.join(', ')}"
      )
    end
    
    def perform_reset_failures(task)
      if task.consecutive_failures == 0
        return success_response(
          task_id: task.id,
          name: task.name,
          message: "Task '#{task.name}' has no failures to reset."
        )
      end
      
      old_count = task.consecutive_failures
      task.update!(consecutive_failures: 0)
      
      success_response(
        task_id: task.id,
        name: task.name,
        previous_failures: old_count,
        can_run: task.can_run?,
        message: "🔄 Reset failure counter for '#{task.name}' (was #{old_count}). Task can now run again."
      )
    end
  end
end

