# Allow health checks from ALB without host authorization
Rails.application.config.host_authorization = {
  exclude: ->(request) {
    # Allow health check endpoints
    request.path.match?(%r{^/up|^/health|^/health_check}) ||
    # Allow ELB health checker user agent
    request.user_agent.to_s.match?(/ELB-HealthChecker/) ||
    # Allow requests from internal IPs (ALB health checks come from these)
    request.remote_ip.match?(/^10\./) ||
    request.remote_ip.match?(/^172\.(1[6-9]|2[0-9]|3[0-1])\./) ||
    request.remote_ip.match?(/^192\.168\./)
  }
} if Rails.env.production?
