namespace :queue do
  desc "Debug SolidQueue status"
  task debug: :environment do
    puts "\n=== SolidQueue Status ==="
    
    # Check for ready jobs
    ready_count = SolidQueue::ReadyExecution.count
    puts "Ready jobs: #{ready_count}"
    
    # Check for claimed jobs
    claimed_count = SolidQueue::ClaimedExecution.count
    puts "Claimed jobs: #{claimed_count}"
    
    # Check for failed jobs
    failed_count = SolidQueue::FailedExecution.count
    puts "Failed jobs: #{failed_count}"
    
    if failed_count > 0
      puts "\nRecent failures:"
      SolidQueue::FailedExecution.order(created_at: :desc).limit(5).each do |failed|
        job = failed.job
        puts "- Job #{job.id} (#{job.class_name}): #{failed.error['message']}"
      end
    end
    
    # Check for scheduled jobs
    scheduled_count = SolidQueue::ScheduledExecution.count
    puts "\nScheduled jobs: #{scheduled_count}"
    
    # Check for active workers
    processes = SolidQueue::Process.where(kind: 'Worker')
    puts "\nActive workers: #{processes.count}"
    processes.each do |process|
      last_heartbeat = Time.current - process.last_heartbeat_at
      puts "- PID #{process.pid} on #{process.hostname} (last heartbeat: #{last_heartbeat.round}s ago)"
    end
    
    # Check for stuck tasks
    puts "\nActive TaskSessions:"
    TaskSession.where(status: 'active').order(created_at: :desc).limit(10).each do |task|
      age = Time.current - task.created_at
      puts "- Task #{task.id}: #{task.metadata['description']} (#{age.round}s old)"
    end
  end
  
  desc "Clear stuck jobs"
  task clear_stuck: :environment do
    # Mark old active tasks as failed
    stuck_tasks = TaskSession.where(status: 'active')
                            .where('created_at < ?', 10.minutes.ago)
    
    puts "Found #{stuck_tasks.count} stuck tasks"
    
    stuck_tasks.find_each do |task|
      task.update!(
        status: 'failed',
        error_message: 'Task timed out',
        completed_at: Time.current
      )
      puts "Marked task #{task.id} as failed"
    end
    
    # Clear failed executions
    failed_count = SolidQueue::FailedExecution.count
    if failed_count > 0
      puts "\nClearing #{failed_count} failed executions..."
      SolidQueue::FailedExecution.destroy_all
    end
    
    puts "\nDone!"
  end
end


