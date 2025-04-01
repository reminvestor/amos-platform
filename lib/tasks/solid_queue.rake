namespace :solid_queue do
  desc "Start Solid::Queue worker process"
  task start: :environment do
    begin
      puts "Starting Solid::Queue worker process..."
      require 'solid_queue'
      
      # For debugging
      puts "Solid::Queue version: #{Solid::Queue::VERSION}"
      
      # Make sure hostname is set properly
      hostname = ENV['DYNO'] || Socket.gethostname
      
      # Set a proper name for the process
      process_name = ENV['PROCESS_NAME'] || "ContactProcessor-#{hostname}"
      
      # Set concurrency from environment or use default
      concurrency = (ENV['CONCURRENCY'] || 5).to_i
      
      # Set dispatcher count from environment or use default
      dispatcher_count = (ENV['DISPATCHER_COUNT'] || 2).to_i
      
      puts "Using: process_name=#{process_name}, hostname=#{hostname}, dispatcher_count=#{dispatcher_count}, concurrency=#{concurrency}"
      
      # First verify the schema has necessary columns
      begin 
        if ActiveRecord::Base.connection.table_exists?(:solid_queue_processes)
          columns = ActiveRecord::Base.connection.columns(:solid_queue_processes)
          column_names = columns.map(&:name)
          puts "Available columns: #{column_names.join(', ')}"
        end
      rescue => schema_error
        puts "Error checking schema: #{schema_error.message}"
      end
      
      # Patch for Solid::Queue 0.3.4 - manually create the supervisor process
      supervisor = Solid::Queue::Supervisor.new(hostname: hostname)
      
      # Set the name explicitly before registration
      supervisor.name = process_name
      
      # Save to database to get an ID
      supervisor.save!
      
      # Start supervisors and workers
      supervisor.start_dispatchers(dispatcher_count, **{ concurrency: concurrency })
      supervisor.start_workers(**{ concurrency: concurrency })
      
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
      puts "ERROR starting Solid::Queue worker: #{e.class.name} - #{e.message}"
      puts e.backtrace.join("\n")
      # Re-raise to make sure the process exits with an error code
      raise e
    end
  end
end 