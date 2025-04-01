namespace :solid_queue do
  desc "Start Solid::Queue worker process"
  task start: :environment do
    begin
      puts "Starting Solid::Queue worker process..."
      require 'solid_queue'
      
      # For debugging
      puts "Solid::Queue version: #{Solid::Queue::VERSION}"
      
      # Make sure hostname is set properly - prefer DYNO for Heroku
      hostname = ENV['DYNO'] || Socket.gethostname
      puts "Hostname detected: #{hostname}"
      
      # Set a proper name for the process - this is critical for the not-null constraint
      process_name = ENV['PROCESS_NAME']
      if process_name.nil? || process_name.empty?
        process_name = "ContactProcessor-#{hostname}"
        puts "WARNING: No PROCESS_NAME env var set, using default: #{process_name}"
      else
        puts "Using PROCESS_NAME from env: #{process_name}"
      end
      
      # Set concurrency from environment or use default
      concurrency = (ENV['CONCURRENCY'] || 5).to_i
      
      # Set dispatcher count from environment or use default
      dispatcher_count = (ENV['DISPATCHER_COUNT'] || 2).to_i
      
      puts "Configuration: process_name=#{process_name}, hostname=#{hostname}, dispatcher_count=#{dispatcher_count}, concurrency=#{concurrency}"
      
      # Verify the schema has necessary columns
      begin 
        if ActiveRecord::Base.connection.table_exists?(:solid_queue_processes)
          columns = ActiveRecord::Base.connection.columns(:solid_queue_processes)
          column_names = columns.map(&:name)
          puts "Available columns in solid_queue_processes: #{column_names.join(', ')}"
          
          unless column_names.include?('name')
            raise "Missing 'name' column in solid_queue_processes table!"
          end
        else
          raise "solid_queue_processes table does not exist! Did you run migrations?"
        end
      rescue => schema_error
        puts "FATAL: Schema verification failed: #{schema_error.message}"
        raise schema_error
      end
      
      puts "Creating supervisor with name: #{process_name}"
      
      # Create the supervisor with explicit name setting
      supervisor = Solid::Queue::Supervisor.new(
        hostname: hostname,
        name: process_name  # Set name during initialization
      )
      
      # Double-check name is set
      unless supervisor.name == process_name
        puts "WARNING: Supervisor name mismatch, explicitly setting name"
        supervisor.name = process_name
      end
      
      puts "Saving supervisor to database..."
      # Save to database to get an ID
      supervisor.save!
      puts "Supervisor saved successfully with ID: #{supervisor.id}"
      
      # Start supervisors and workers
      puts "Starting dispatchers..."
      supervisor.start_dispatchers(dispatcher_count, **{ concurrency: concurrency })
      puts "Starting workers..."
      supervisor.start_workers(**{ concurrency: concurrency })
      
      puts "Supervisor startup complete. Entering main loop..."
      
      # Keep the process alive until interrupted
      begin
        loop do
          sleep 1
          supervisor.refresh
        end
      rescue Interrupt
        puts "Shutting down supervisor..."
        supervisor.stop
      end
    rescue => e
      puts "FATAL ERROR starting Solid::Queue worker: #{e.class.name} - #{e.message}"
      puts e.backtrace.join("\n")
      # Re-raise to make sure the process exits with an error code
      raise e
    end
  end
end 