class Admin::ParallelTasksController < Admin::BaseController
  before_action :authorize_admin!
  
  def index
    @filter = params[:filter] || 'all'
    @time_range = params[:time_range] || '24h'
    
    # Base query
    @tasks = TaskSession.parallel_tasks
                       .includes(:user, :task_dependencies, :depends_on_tasks)
    
    # Apply filters
    case @filter
    when 'active'
      @tasks = @tasks.where(status: 'active')
    when 'completed'
      @tasks = @tasks.where(status: 'completed')
    when 'failed'
      @tasks = @tasks.where(status: 'failed')
    when 'voice'
      @tasks = @tasks.where("task_type LIKE 'voice_%'")
    end
    
    # Apply time range
    case @time_range
    when '1h'
      @tasks = @tasks.where('created_at > ?', 1.hour.ago)
    when '24h'
      @tasks = @tasks.where('created_at > ?', 24.hours.ago)
    when '7d'
      @tasks = @tasks.where('created_at > ?', 7.days.ago)
    end
    
    @tasks = @tasks.order(created_at: :desc)
                   .page(params[:page])
                   .per(50)
    
    # Calculate statistics
    @stats = calculate_stats
  end
  
  def show
    @task = TaskSession.find(params[:id])
    @events = @task.task_events.order(:sequence_number)
    @dependencies = @task.task_dependencies.includes(:depends_on_task)
    @dependents = @task.dependent_tasks
  end
  
  def cancel
    @task = TaskSession.find(params[:id])
    
    if @task.update(status: 'cancelled')
      # Cancel dependent tasks
      @task.dependent_tasks.where(status: 'active').update_all(
        status: 'cancelled',
        updated_at: Time.current
      )
      
      redirect_to admin_parallel_tasks_path, 
                  notice: "Task #{@task.id} and its dependents have been cancelled."
    else
      redirect_to admin_parallel_task_path(@task), 
                  alert: "Failed to cancel task: #{@task.errors.full_messages.join(', ')}"
    end
  end
  
  def retry
    original_task = TaskSession.find(params[:id])
    
    # Create a new task with same parameters
    new_task = original_task.dup
    new_task.status = 'active'
    new_task.started_at = nil
    new_task.progress = 0
    new_task.state = {}
    
    if new_task.save
      # Copy dependencies
      original_task.task_dependencies.each do |dep|
        new_task.task_dependencies.create!(
          depends_on_task_id: dep.depends_on_task_id,
          relationship_type: dep.relationship_type
        )
      end
      
      # Queue for execution
      TaskExecutionJob.perform_later(new_task.id)
      
      redirect_to admin_parallel_task_path(new_task),
                  notice: "Task retried as ##{new_task.id}"
    else
      redirect_to admin_parallel_task_path(original_task),
                  alert: "Failed to retry task: #{new_task.errors.full_messages.join(', ')}"
    end
  end
  
  private
  
  def calculate_stats
    base_query = TaskSession.parallel_tasks
    
    # Apply same time filter
    case @time_range
    when '1h'
      base_query = base_query.where('created_at > ?', 1.hour.ago)
    when '24h'
      base_query = base_query.where('created_at > ?', 24.hours.ago)
    when '7d'
      base_query = base_query.where('created_at > ?', 7.days.ago)
    end
    
    {
      total: base_query.count,
      active: base_query.where(status: 'active').count,
      completed: base_query.where(status: 'completed').count,
      failed: base_query.where(status: 'failed').count,
      voice_tasks: base_query.where("task_type LIKE 'voice_%'").count,
      avg_duration: calculate_avg_duration(base_query),
      success_rate: calculate_success_rate(base_query)
    }
  end
  
  def calculate_avg_duration(query)
    completed = query.where(status: 'completed')
                     .where.not(started_at: nil)
                     .select('EXTRACT(EPOCH FROM (updated_at - started_at)) as duration')
    
    return 0 if completed.empty?
    
    durations = completed.map(&:duration).compact
    return 0 if durations.empty?
    
    (durations.sum / durations.length).round(2)
  end
  
  def calculate_success_rate(query)
    total = query.where(status: ['completed', 'failed']).count
    return 0 if total.zero?
    
    completed = query.where(status: 'completed').count
    ((completed.to_f / total) * 100).round(2)
  end
end
