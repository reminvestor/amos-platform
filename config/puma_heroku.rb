# Minimal Puma configuration for Heroku
workers Integer(ENV['WEB_CONCURRENCY'] || 2)
threads_count = Integer(ENV['RAILS_MAX_THREADS'] || 5)
threads threads_count, threads_count

# Just bind to the port Heroku gives us - nothing else
port ENV['PORT'] || 3000

# Preload the app
preload_app!

on_worker_boot do
  ActiveRecord::Base.establish_connection
end

# Allow puma to be restarted by `rails restart` command
plugin :tmp_restart

# Special error handling for SSL issues
lowlevel_error_handler do |e|
  # Log the error
  [500, {}, ["An error occurred: #{e.message}"]]
end 