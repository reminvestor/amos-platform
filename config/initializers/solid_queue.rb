# Configure Solid::Queue
Solid::Queue.configure do |config|
  # Set the default queue name
  config.default_queue = 'default'
  
  # Configure the dispatcher
  config.dispatcher do |dispatcher|
    dispatcher.polling_interval = 1
    dispatcher.batch_size = 500
    dispatcher.concurrency_maintenance_interval = 600
  end
  
  # Configure the worker
  config.worker do |worker|
    worker.polling_interval = 0.1
    worker.queues = ['*']  # Process all queues
    worker.thread_pool_size = 3
  end
  
  # Log configuration
  Rails.logger.info("Solid::Queue configured with default_queue: #{config.default_queue}")
end 