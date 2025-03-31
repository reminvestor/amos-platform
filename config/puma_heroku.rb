# Minimal Puma configuration for Heroku
workers Integer(ENV['WEB_CONCURRENCY'] || 2)
threads_count = Integer(ENV['RAILS_MAX_THREADS'] || 5)
threads threads_count, threads_count

# Add environment info
environment ENV['RACK_ENV'] || 'development'

# Set debug log level
log_requests true

# Just bind to the port Heroku gives us - nothing else
port ENV['PORT'] || 3000

# Preload the app
preload_app!

on_worker_boot do
  ActiveRecord::Base.establish_connection
end

# Allow puma to be restarted by `rails restart` command
plugin :tmp_restart

# Add an error handler that logs details about SSL issues
lowlevel_error_handler do |e|
  # Log the error with as much detail as possible
  [500, {'Content-Type' => 'text/plain'}, ["Puma Error: #{e.message}\n#{e.backtrace.join("\n")}"]]
end 