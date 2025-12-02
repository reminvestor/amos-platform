# frozen_string_literal: true

module Tools
  class ManageScheduledTaskTool < BaseTool
    def self.metadata
      {
        name: "manage_scheduled_task",
        description: "Manage an existing scheduled task - pause, resume, run now, update, or delete it.",
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
              enum: %w[pause resume run_now delete update],
              description: "The action to perform: pause, resume, run_now (execute immediately), delete, or update"
            },
            updates: {
              type: "object",
              description: "For 'update' action: fields to update (name, prompt, schedule_type, run_at_time, run_on_day, enabled)",
              properties: {
                name: { type: "string" },
                prompt: { type: "string" },
                schedule_type: { type: "string", enum: %w[once daily weekly monthly] },
                run_at_time: { type: "string" },
                run_on_day: { type: "integer" },
                enabled: { type: "boolean" }
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
          ScheduledAgentTask.find_by(
            name: task_name,
            entity: @entity,
            user: @user
          )
        end

        unless task
          return error_response("Scheduled task not found. Use list_scheduled_tasks to see available tasks.")
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
          status: task.status,
          message: "Task '#{task.name}' is already paused."
        )
      end

      task.pause!
      success_response(
        task_id: task.id,
        name: task.name,
        status: task.status,
        message: "⏸️ Paused scheduled task '#{task.name}'. It will not run until resumed."
      )
    end

    def perform_resume(task)
      if task.status == 'active'
        return success_response(
          task_id: task.id,
          name: task.name,
          status: task.status,
          next_run: task.next_run_at&.strftime('%b %d at %I:%M %p'),
          message: "Task '#{task.name}' is already active."
        )
      end

      task.resume!
      success_response(
        task_id: task.id,
        name: task.name,
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

      # Convert string keys to symbols and filter allowed updates
      allowed_keys = %i[name prompt schedule_type run_at_time run_on_day enabled]
      filtered_updates = {}

      updates.each do |key, value|
        key_sym = key.to_sym
        if allowed_keys.include?(key_sym)
          # Handle special cases
          if key_sym == :run_at_time && value.is_a?(String)
            filtered_updates[key_sym] = Time.parse(value)
          else
            filtered_updates[key_sym] = value
          end
        end
      end

      if filtered_updates.empty?
        return error_response("No valid updates provided. Allowed fields: #{allowed_keys.join(', ')}")
      end

      task.update!(filtered_updates)

      success_response(
        task_id: task.id,
        name: task.name,
        updated_fields: filtered_updates.keys,
        next_run: task.next_run_at&.strftime('%b %d at %I:%M %p'),
        message: "✏️ Updated scheduled task '#{task.name}'. Fields changed: #{filtered_updates.keys.join(', ')}"
      )
    end
  end
end

