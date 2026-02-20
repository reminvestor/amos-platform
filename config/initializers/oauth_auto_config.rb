# frozen_string_literal: true

# Auto-configure OAuth credentials from environment variables
# This allows platform admins to set credentials once via ENV,
# and all users get seamless "Connect" button experience

Rails.application.config.after_initialize do
  next unless defined?(OauthConfiguration) && defined?(Integration)

  # Only run in web server context, not during asset compilation or DB setup
  next if defined?(Rails::Console) || File.basename($PROGRAM_NAME) == "rake"
  next if ENV["SECRET_KEY_BASE_DUMMY"].present? # Container build asset precompilation

  # Skip if tables don't exist yet (fresh DB, running migrations)
  begin
    next unless ActiveRecord::Base.connection.table_exists?(:integrations)
  rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad
    next
  end

  Rails.logger.info "[OAuth] Checking auto-configuration..."

  configure_oauth = lambda do |slug, client_id_env, client_secret_env, extra_config = {}|
    client_id = ENV[client_id_env]
    client_secret = ENV[client_secret_env]

    return unless client_id.present? && client_secret.present?

    integration = Integration.find_by(slug: slug)
    return unless integration

    oauth_config = OauthConfiguration.find_or_initialize_by(integration: integration)

    # Only update if credentials changed or not set
    if oauth_config.client_id != client_id || oauth_config.client_secret != client_secret
      oauth_config.update!(
        client_id: client_id,
        client_secret: client_secret,
        redirect_uri: extra_config[:redirect_uri] || "#{ENV.fetch('APP_URL', 'http://localhost:3000')}/oauth/callback",
        status: "active",
        **extra_config.except(:redirect_uri)
      )
      Rails.logger.info "[OAuth] Auto-configured #{integration.name} OAuth credentials"
    end
  end

  # Gmail OAuth
  configure_oauth.call("gmail", "GMAIL_CLIENT_ID", "GMAIL_CLIENT_SECRET")

  # Microsoft Outlook OAuth (if configured)
  configure_oauth.call("outlook", "OUTLOOK_CLIENT_ID", "OUTLOOK_CLIENT_SECRET")

  # Add more providers as needed...
  # configure_oauth.call("yahoo", "YAHOO_CLIENT_ID", "YAHOO_CLIENT_SECRET")
end
