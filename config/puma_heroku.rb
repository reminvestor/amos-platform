# Minimal Puma configuration for Heroku - strictly following Heroku recommendations

# Set the environment
environment ENV.fetch("RAILS_ENV") { "production" }

# Set threads per worker
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Only use workers in production (> 1 process)
if ENV.fetch("RAILS_ENV") { "development" } == "production"
  workers ENV.fetch("WEB_CONCURRENCY") { 2 }
  preload_app!
end

# Use the port provided by Heroku (no special binding needed)
port ENV.fetch("PORT") { 3000 }

# On worker boot, reconnect to the database
on_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

# Allow puma to be restarted by `bin/rails restart` command
plugin :tmp_restart

# Redirect stderr/stdout to files in production
if ENV.fetch("RAILS_ENV") { "development" } == "production"
  stdout_redirect "log/puma.stdout.log", "log/puma.stderr.log", true
end 