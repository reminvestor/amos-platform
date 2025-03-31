# Minimal Puma configuration for Heroku
workers Integer(ENV['WEB_CONCURRENCY'] || 2)
threads_count = Integer(ENV['RAILS_MAX_THREADS'] || 5)
threads threads_count, threads_count

# Add environment info
environment ENV['RACK_ENV'] || 'development'

# Set debug log level
log_requests true

# Force HTTP protocol mode - critical for Heroku SSL termination
if Puma.respond_to?(:ssl_default_bind_mode=)
  Puma.ssl_default_bind_mode = false
end

# Explicitly disable SSL for Heroku
if ENV['RACK_ENV'] == 'production'
  ENV['DISABLE_SSL'] = 'true'
end

# Port should be specified with a tcp:// scheme to ensure HTTP protocol is used
bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 3000)}"

# Preload the app
preload_app!

on_worker_boot do
  ActiveRecord::Base.establish_connection
end

# Allow puma to be restarted by `rails restart` command
plugin :tmp_restart

# Add an improved error handler that provides more context about SSL issues
lowlevel_error_handler do |e|
  # Log the error with as much detail as possible
  error_message = "Puma Error: #{e.message}\n#{e.backtrace.join("\n")}"
  env_info = "\nEnvironment: #{ENV['RACK_ENV']}\n"
  env_info += "SSL Disabled: #{ENV['DISABLE_SSL']}, Force SSL: #{ENV['FORCE_SSL']}"
  
  [500, {'Content-Type' => 'text/plain'}, [error_message + env_info]]
end 