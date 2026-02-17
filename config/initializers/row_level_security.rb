# frozen_string_literal: true

# Row-Level Security (RLS) Configuration
#
# This initializer sets up a Rack middleware that automatically configures
# PostgreSQL session variables for Row-Level Security (RLS) policies.
#
# RLS policies enforce multi-tenant data isolation at the database level,
# ensuring users can only access data for their current entity.

module RowLevelSecurity
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      # Extract entity_id from the request if available
      # This runs before the Rails router, so we check session and headers
      request = ActionDispatch::Request.new(env)

      # Try to get entity_id from session (web requests)
      entity_id = request.session[:entity_id] if request.session.respond_to?(:[])

      # For API requests, we'll rely on the controller to set it
      # (after authenticating the user via API key)

      # Set PostgreSQL session variable if entity_id is present
      if entity_id.present? && ActiveRecord::Base.connected?
        ActiveRecord::Base.connection.execute(
          "SET LOCAL app.current_entity_id = #{ActiveRecord::Base.connection.quote(entity_id)};"
        )
      end

      @app.call(env)
    ensure
      # Clear the session variable after the request
      if ActiveRecord::Base.connected?
        ActiveRecord::Base.connection.execute(
          "SET LOCAL app.current_entity_id = NULL;"
        ) rescue nil
      end
    end
  end
end

# Add middleware to Rails stack
Rails.application.config.middleware.use RowLevelSecurity::Middleware if Rails.env.production? || ENV['ENABLE_RLS'] == 'true'

# Helper module for controllers to set RLS context
module RowLevelSecurityHelper
  extend ActiveSupport::Concern

  included do
    # Set RLS context after authentication
    after_action :set_rls_context, if: -> { current_entity.present? }
  end

  private

  def set_rls_context
    return unless current_entity

    ActiveRecord::Base.connection.execute(
      "SET LOCAL app.current_entity_id = #{ActiveRecord::Base.connection.quote(current_entity.id)};"
    )
  rescue => e
    Rails.logger.warn "Failed to set RLS context: #{e.message}"
  end
end

# Auto-include in ApplicationController
Rails.application.config.to_prepare do
  ApplicationController.include RowLevelSecurityHelper if defined?(ApplicationController)
end
