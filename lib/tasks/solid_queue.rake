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
      
      # Start the process with the specified settings using parameter format from solid_queue 0.3.x
      Solid::Queue::Process.supervise(
        name: process_name, 
        hostname: hostname,
        dispatcher_count: dispatcher_count,
        dispatcher_opts: { concurrency: concurrency }
      )
    rescue => e
      puts "ERROR starting Solid::Queue worker: #{e.class.name} - #{e.message}"
      puts e.backtrace.join("\n")
      # Re-raise to make sure the process exits with an error code
      raise e
    end
  end
end 