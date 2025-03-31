# Add our API SSL middleware directly to avoid frozen array errors
Rails.application.config.middleware.use ApiSslMiddleware 