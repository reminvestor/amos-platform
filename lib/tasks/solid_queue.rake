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
  task :trigger_task, [ :key ] => :environment do |t, args|
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

    if task["class_name"].present?
      begin
        job_class = task["class_name"].constantize
        job = job_class.perform_later
        puts "Job enqueued successfully"
      rescue => e
        puts "Error enqueueing job: #{e.message}"
      end
    elsif task["command"].present?
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
      INSERT INTO solid_queue_recurring_tasks#{' '}
        (key, class_name, schedule, queue_name, description, created_at, updated_at, static)
      VALUES#{' '}
        ('#{recurring_job[:key]}', '#{recurring_job[:class_name]}', '#{recurring_job[:schedule]}',#{' '}
         '#{recurring_job[:queue]}', '#{recurring_job[:description]}', NOW(), NOW(), true)
      ON CONFLICT (key)#{' '}
      DO UPDATE SET#{' '}
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

  desc "Start Solid Queue worker using Rails runner"
  task start_via_runner: :environment do
    # This task executes SolidQueue worker in the current process

    # Configure Rails logger to include both console AND file output
    log_level = ENV.fetch("SOLID_QUEUE_LOG_LEVEL", "info").upcase

    # Create a console logger
    console_logger = ActiveSupport::Logger.new(STDOUT)
    console_logger.level = ActiveSupport::Logger.const_get(log_level)
    console_logger.formatter = proc do |severity, datetime, progname, msg|
      time = datetime.strftime("%Y-%m-%d %H:%M:%S")
      "[#{time}] [#{severity}] #{msg}\n"
    end

    # Create a file logger for jobs
    log_dir = Rails.root.join("log")
    FileUtils.mkdir_p(log_dir) unless File.directory?(log_dir)

    # Rotate logs if they get too big
    file_logger = ActiveSupport::Logger.new(
      Rails.root.join("log", "solid_queue_jobs.log"),
      10,  # Keep 10 files
      10.megabytes  # Each file up to 10 MB
    )
    file_logger.level = ActiveSupport::Logger.const_get(log_level)
    file_logger.formatter = proc do |severity, datetime, progname, msg|
      time = datetime.strftime("%Y-%m-%d %H:%M:%S")
      "[#{time}] [#{severity}] #{msg}\n"
    end

    # Create a multi-logger that logs to both console and file
    Rails.logger = ActiveSupport::BroadcastLogger.new(console_logger, file_logger)

    # Make sure rails jobs log to our logger too
    ActiveJob::Base.logger = Rails.logger

    # Define JobAttributes module if needed
    if defined?(SolidQueue) && !defined?(SolidQueue::JobAttributes)
      Rails.logger.info "Creating JobAttributes module for SolidQueue"
      module SolidQueue
        module JobAttributes
          extend ActiveSupport::Concern
          included do
            belongs_to :job, class_name: "SolidQueue::Job", optional: false
            delegate :class_name, :arguments, to: :job
          end
        end
      end
    end

    # Set SolidQueue logger
    SolidQueue.logger = Rails.logger if defined?(SolidQueue)

    # Get thread and polling interval settings
    threads = ENV.fetch("SOLID_QUEUE_THREADS", "5").to_i
    polling = ENV.fetch("SOLID_QUEUE_POLLING_INTERVAL", "1").to_i

    Rails.logger.info "="*80
    Rails.logger.info "STARTING SOLID QUEUE WORKER"
    Rails.logger.info "  Threads: #{threads}"
    Rails.logger.info "  Polling interval: #{polling}s"
    Rails.logger.info "  Log level: #{log_level}"
    Rails.logger.info "  Log file: #{Rails.root.join("log", "solid_queue_jobs.log")}"
    Rails.logger.info "="*80

    # Apply patch if needed
    if defined?(SolidQueue::Execution) && !SolidQueue::Execution.included_modules.include?(SolidQueue::JobAttributes)
      Rails.logger.info "Applying JobAttributes to SolidQueue::Execution"
      SolidQueue::Execution.include(SolidQueue::JobAttributes)
    end

    # Start worker and dispatcher
    begin
      require "solid_queue/dispatcher"
      require "solid_queue/worker"

      # Create worker and dispatcher
      Rails.logger.info "Creating SolidQueue dispatcher (polling: #{polling}s)"
      dispatcher = SolidQueue::Dispatcher.new(polling_interval: polling)

      Rails.logger.info "Creating SolidQueue worker (threads: #{threads})"
      worker = SolidQueue::Worker.new(queues: [ "*" ], threads: threads)

      # Start dispatcher in separate thread
      dispatcher_thread = Thread.new do
        Rails.logger.info "Starting dispatcher..."
        begin
          dispatcher.start
        rescue => e
          Rails.logger.error "Dispatcher error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end

      # Set up signal handlers
      %w[INT TERM].each do |signal|
        trap(signal) do
          Rails.logger.info "Received #{signal} signal, shutting down..."
          exit
        end
      end

      # Start the worker in the main thread
      Rails.logger.info "Starting worker..."
      Rails.logger.info "SolidQueue is ready to process jobs. Press Ctrl-C to stop."
      Rails.logger.info "="*80

      # Start worker (non-blocking)
      worker.start

      # Keep the process alive until interrupted
      # This is critical because SolidQueue worker.start doesn't block!
      Rails.logger.info "Worker started, keeping process alive..."
      loop do
        sleep 10
        Rails.logger.debug "SolidQueue worker heartbeat... (#{Time.current})"
      end

    rescue => e
      Rails.logger.error "Error starting SolidQueue: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
  end

  # Use the runner approach as the default
  desc "Start Solid Queue worker (via rails runner)"
  task start: :start_via_runner
end
