class ScheduledTaskMailer < ApplicationMailer
  # Email sent when a scheduled task completes successfully
  def task_completed(scheduled_task, run, result, summary)
    @task = scheduled_task
    @run = run
    @result = result
    @summary = summary
    @user = scheduled_task.user
    @entity = scheduled_task.entity
    @base_url = build_base_url
    
    # Handle content - could be a string, hash, or array of results
    raw_content = result[:content] || result['content']
    @content = extract_content_string(raw_content)
    
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
    @base_url = build_base_url
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
    @base_url = build_base_url
    @tasks_summary = tasks_summary
    @total_runs = tasks_summary.sum { |t| t[:runs_count] || 0 }
    @total_successes = tasks_summary.sum { |t| t[:success_count] || 0 }
    @total_failures = tasks_summary.sum { |t| t[:failure_count] || 0 }
    
    mail(
      to: @user.email,
      subject: "📊 Your Scheduled Tasks Summary - #{Date.current.strftime('%B %d, %Y')}"
    )
  end
  
  private
  
  # Build base URL for links in emails
  def build_base_url
    host = ENV['APPLICATION_HOST'] || ENV['APP_HOST'] || 'localhost:3000'
    if host.start_with?('http')
      host.chomp('/')
    else
      "https://#{host}"
    end
  end
  
  # Extract a string from various content formats
  def extract_content_string(content)
    return '' if content.blank?
    return content if content.is_a?(String)
    
    # If it's an array of results, extract messages
    if content.is_a?(Array)
      return content.map { |item| extract_content_string(item) }.join("\n\n---\n\n")
    end
    
    # If it's a hash, look for message or content keys
    if content.is_a?(Hash)
      return content[:message] || content['message'] || 
             content[:content] || content['content'] ||
             content[:text] || content['text'] ||
             content.to_json
    end
    
    content.to_s
  end
end

