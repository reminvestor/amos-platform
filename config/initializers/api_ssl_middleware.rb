Rails.application.config.after_initialize do
  # Add our API SSL middleware at the beginning of the stack
  Rails.application.config.middleware.insert_before 0, ApiSslMiddleware
end 