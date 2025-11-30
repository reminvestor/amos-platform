class ScheduledTaskMailer < ApplicationMailer
  # Email sent when a scheduled task completes successfully
  def task_completed(scheduled_task, run, result, summary)
    @task = scheduled_task
    @run = run
    @result = result
    @summary = summary
    @user = scheduled_task.user
    @entity = scheduled_task.entity
    @content = result[:content] || result['content']
    @canvas_data = result[:canvas_data] || result['canvas_data']
    @tools_used = result[:tools_used] || result['tools_used'] || []
    
    # Calculate execution time
    if run.started_at && run.completed_at
      @execution_time = ((run.completed_at - run.started_at) * 1000).round # ms
    end
    
    mail(
      to: @user.email,
      subject: "✅ #{@task.name} - Task Completed"
    )
  end
  
  # Email sent when a scheduled task fails
  def task_failed(scheduled_task, run, error_message)
    @task = scheduled_task
    @run = run
    @error_message = error_message
    @user = scheduled_task.user
    @entity = scheduled_task.entity
    @consecutive_failures = scheduled_task.consecutive_failures
    @is_paused = scheduled_task.status == 'paused'
    
    mail(
      to: @user.email,
      subject: "❌ #{@task.name} - Task Failed"
    )
  end
  
  # Daily/weekly digest of scheduled task activity
  def task_digest(user, entity, tasks_summary)
    @user = user
    @entity = entity
    @tasks_summary = tasks_summary
    @total_runs = tasks_summary.sum { |t| t[:runs_count] || 0 }
    @total_successes = tasks_summary.sum { |t| t[:success_count] || 0 }
    @total_failures = tasks_summary.sum { |t| t[:failure_count] || 0 }
    
    mail(
      to: @user.email,
      subject: "📊 Your Scheduled Tasks Summary - #{Date.current.strftime('%B %d, %Y')}"
    )
  end
end

