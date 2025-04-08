namespace :solid_queue do
  desc "List all recurring tasks"
  task list_recurring: :environment do
    # Get recurring tasks directly from the database
    tasks = ActiveRecord::Base.connection.execute("SELECT * FROM solid_queue_recurring_tasks")
    
    if tasks.count == 0
      puts "No recurring tasks found."
    else
      puts "Current recurring tasks:"
      puts "-----------------------"
      
      tasks.each do |task|
        puts "Key: #{task['key']}"
        puts "Class: #{task['class_name']}"
        puts "Schedule: #{task['schedule']}"
        puts "Description: #{task['description']}"
        puts "Last updated: #{task['updated_at']}"
        puts "-----------------------"
      end
    end
  end
  
  desc "Manually trigger a recurring task by key"
  task :trigger_task, [:key] => :environment do |t, args|
    if args[:key].blank?
      puts "Please provide a task key"
      puts "Usage: rake solid_queue:trigger_task[task_key]"
      puts "Example: rake solid_queue:trigger_task[process_drip_campaigns]"
      exit 1
    end
    
    task_key = args[:key]
    task = ActiveRecord::Base.connection.execute("SELECT * FROM solid_queue_recurring_tasks WHERE key = '#{task_key}' LIMIT 1").first
    
    if task.nil?
      puts "Task with key '#{task_key}' not found."
      exit 1
    end
    
    puts "Triggering task: #{task['key']} (#{task['class_name']})"
    
    if task['class_name'].present?
      begin
        job_class = task['class_name'].constantize
        job = job_class.perform_later
        puts "Job enqueued successfully"
      rescue => e
        puts "Error enqueueing job: #{e.message}"
      end
    elsif task['command'].present?
      puts "Cannot directly run command-based tasks."
    else
      puts "Task has no class or command specified."
    end
  end
  
  desc "Process drip campaigns manually"
  task process_drips: :environment do
    puts "Manually processing drip campaigns..."
    ProcessDripCampaignsJob.perform_now
    puts "Done!"
  end
  
  desc "Create or update the drip campaigns recurring job"
  task setup_drip_job: :environment do
    # Define a recurring task for the drip campaign processor
    # This will run hourly to check for due drip campaigns
    recurring_job = {
      key: "process_drip_campaigns",
      class_name: "ProcessDripCampaignsJob",
      schedule: "0 * * * *", # Cron syntax: Run at the top of every hour
      queue: "default",
      description: "Process drip campaigns due to be sent"
    }
    
    # Create or update the recurring job in the database
    sql = <<~SQL
      INSERT INTO solid_queue_recurring_tasks 
        (key, class_name, schedule, queue_name, description, created_at, updated_at, static)
      VALUES 
        ('#{recurring_job[:key]}', '#{recurring_job[:class_name]}', '#{recurring_job[:schedule]}', 
         '#{recurring_job[:queue]}', '#{recurring_job[:description]}', NOW(), NOW(), true)
      ON CONFLICT (key) 
      DO UPDATE SET 
        class_name = '#{recurring_job[:class_name]}',
        schedule = '#{recurring_job[:schedule]}',
        queue_name = '#{recurring_job[:queue]}',
        description = '#{recurring_job[:description]}',
        updated_at = NOW();
    SQL
    
    begin
      ActiveRecord::Base.connection.execute(sql)
      puts "Successfully configured recurring drip campaign processor job"
    rescue => e
      puts "Error configuring recurring task: #{e.message}"
    end
  end
end 