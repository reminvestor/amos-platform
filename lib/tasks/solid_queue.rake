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
      
      # Use a transaction to ensure atomicity
      ActiveRecord::Base.transaction do
        # First, create the process record directly in the database
        process_record = Solid::Queue::Process.new(
          name: process_name,
          hostname: hostname,
          type: 'Supervisor',
          pid: Process.pid
        )
        
        # Force set the name attribute
        process_record.attributes = {
          'name' => process_name,
          'hostname' => hostname,
          'type' => 'Supervisor',
          'pid' => Process.pid
        }
        
        # Save with validation
        process_record.save!(validate: true)
        puts "Created process record with ID: #{process_record.id}"
        
        # Verify the name was set
        if process_record.name.nil?
          raise "Process name is still nil after save!"
        end
        
        # Now create the supervisor with the existing process record
        supervisor = Solid::Queue::Supervisor.new(
          hostname: hostname,
          process: process_record
        )
        
        puts "Created supervisor instance with process record"
        
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
      end
    rescue => e
      puts "FATAL ERROR starting Solid::Queue worker: #{e.class.name} - #{e.message}"
      puts e.backtrace.join("\n")
      # Re-raise to make sure the process exits with an error code
      raise e
    end
  end
end 