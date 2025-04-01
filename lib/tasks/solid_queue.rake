namespace :solid_queue do
  desc "Start Solid::Queue worker process"
  task start: :environment do
    begin
      puts "Starting Solid::Queue worker process..."
      require 'solid_queue'
      
      # Set a proper name for the process
      name = ENV['PROCESS_NAME'] || 'ContactsProcessor'
      
      # Set concurrency from environment or use default
      concurrency = (ENV['CONCURRENCY'] || 5).to_i
      
      # Set dispatcher count from environment or use default
      dispatcher_count = (ENV['DISPATCHER_COUNT'] || 2).to_i
      
      puts "Using: name=#{name}, dispatcher_count=#{dispatcher_count}, concurrency=#{concurrency}"
      
      # Start the process with the specified settings
      Solid::Queue::Process.supervise(
        name: name,
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