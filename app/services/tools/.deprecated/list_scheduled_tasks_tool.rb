# frozen_string_literal: true

module Tools
  class ListScheduledTasksTool < BaseTool
    def self.metadata
      {
        name: "list_scheduled_tasks",
        description: "List the user's scheduled tasks. Shows active automations, their schedules, and recent run history.",
        category: "scheduling",
        input_schema: {
          type: "object",
          properties: {
            status: {
              type: "string",
              enum: %w[active paused all],
              description: "Filter by status. Defaults to 'active'."
            },
            task_type: {
              type: "string",
              enum: %w[email_summary report_generation data_sync email_management research_update custom],
              description: "Filter by task type"
            },
            limit: {
              type: "integer",
              description: "Maximum number of tasks to return. Defaults to 10."
            }
          }
        }
      }
    end

    def execute(args)
      log_execution(args)

      status = get_arg(args, :status, 'active')
      task_type = get_arg(args, :task_type)
      limit = get_arg(args, :limit, 10).to_i

      begin
        tasks = ScheduledAgentTask.where(entity: @entity, user: @user)

        # Apply filters
        case status
        when 'active'
          tasks = tasks.active
        when 'paused'
          tasks = tasks.paused
        # 'all' shows everything
        end

        tasks = tasks.by_type(task_type) if task_type.present?
        tasks = tasks.order(created_at: :desc).limit(limit)

        if tasks.empty?
          return success_response(
            tasks: [],
            count: 0,
            message: "No scheduled tasks found. You can create one with the create_scheduled_task tool."
          )
        end

        task_list = tasks.map do |task|
          {
            id: task.id,
            name: task.name,
            type: task.task_type,
            icon: task.task_type_info[:icon],
            schedule: format_schedule(task),
            next_run: task.next_run_at&.strftime('%b %d at %I:%M %p'),
            last_run: task.last_run_at ? "#{time_ago_in_words(task.last_run_at)} ago" : 'Never',
            status: task.status,
            enabled: task.enabled?,
            run_count: task.run_count,
            failure_count: task.failure_count
          }
        end

        success_response(
          tasks: task_list,
          count: task_list.count,
          message: "Found #{task_list.count} scheduled task(s)"
        )
      rescue => e
        Rails.logger.error "Error listing scheduled tasks: #{e.message}"
        error_response("Failed to list scheduled tasks: #{e.message}")
      end
    end

    private

    def format_schedule(task)
      case task.schedule_type
      when 'once'
        'One-time'
      when 'daily'
        "Daily at #{task.run_at_time&.strftime('%I:%M %p')}"
      when 'weekly'
        "#{Date::DAYNAMES[task.run_on_day || 0]}s at #{task.run_at_time&.strftime('%I:%M %p')}"
      when 'monthly'
        "Monthly on the #{task.run_on_day.ordinalize} at #{task.run_at_time&.strftime('%I:%M %p')}"
      when 'cron'
        task.cron_expression
      else
        task.schedule_type
      end
    end

    def time_ago_in_words(time)
      seconds = (Time.current - time).to_i

      case seconds
      when 0..59 then "less than a minute"
      when 60..3599 then "#{seconds / 60} minute#{'s' if seconds / 60 > 1}"
      when 3600..86399 then "#{seconds / 3600} hour#{'s' if seconds / 3600 > 1}"
      when 86400..604799 then "#{seconds / 86400} day#{'s' if seconds / 86400 > 1}"
      else "#{seconds / 604800} week#{'s' if seconds / 604800 > 1}"
      end
    end
  end
end

