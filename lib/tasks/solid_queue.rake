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
      
      # ALWAYS set a process name - no nil checking needed
      process_name = ENV.fetch('PROCESS_NAME', "ContactProcessor-#{hostname}")
      puts "Using process name: #{process_name}"
      
      # Set concurrency from environment or use default
      concurrency = (ENV['CONCURRENCY'] || 5).to_i
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
      
      # Create the supervisor differently to ensure name is set
      supervisor = Class.new(Solid::Queue::Supervisor) do
        def initialize(name:, hostname:, **options)
          # Force set the name before any database operations
          @name = name
          super(hostname: hostname, **options)
        end

        # Override name getter to ensure it's never nil
        def name
          @name ||= "ContactProcessor-#{hostname}"
        end
      end.new(
        name: process_name,
        hostname: hostname
      )

      puts "Created supervisor instance with name: #{supervisor.name}"
      
      # Verify the name is set
      raise "Supervisor name is nil!" if supervisor.name.nil?
      puts "Verified supervisor name is set to: #{supervisor.name}"
      
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