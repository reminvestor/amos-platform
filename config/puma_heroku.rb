# Heroku-specific Puma configuration
workers Integer(ENV['WEB_CONCURRENCY'] || 2)
threads_count = Integer(ENV['RAILS_MAX_THREADS'] || 5)
threads threads_count, threads_count

preload_app!

rackup DefaultRackup
port ENV['PORT'] || 3000
environment ENV['RACK_ENV'] || 'development'

# Heroku requires SSL termination at the load balancer level
# Tell Puma to expect this by enabling HTTP explicitly
ssl_bind '0.0.0.0', ENV['PORT'] || 3000, {
  key: '/dev/null', # Placeholder since Heroku handles SSL
  cert: '/dev/null', # Placeholder since Heroku handles SSL
  verify_mode: 'none'
}

on_worker_boot do
  # Worker specific setup for Rails 4.1+
  ActiveRecord::Base.establish_connection
end

# Allow puma to be restarted by `rails restart` command
plugin :tmp_restart

# Special error handling for SSL issues
lowlevel_error_handler do |e|
  # Log the error
  [500, {}, ["An error occurred: #{e.message}"]]
end 