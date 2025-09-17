# Development-specific Puma configuration
# This avoids segfaults with pg gem when using workers

# Single-threaded, single-worker configuration for development
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Disable workers in development to avoid pg gem segfaults
workers 0

# Specifies the `port` that Puma will listen on to receive requests
port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command
plugin :tmp_restart

# Specify the PID file
pidfile ENV.fetch("PIDFILE", "tmp/pids/server.pid")
