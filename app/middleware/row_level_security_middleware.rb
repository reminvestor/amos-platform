class RowLevelSecurityMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    # Extract entity ID from thread-local storage (set by EntityScoped concern)
    entity_id = Thread.current[:current_entity_id]

    if entity_id
      # Set PostgreSQL session variable for RLS
      set_rls_context(entity_id) do
        @app.call(env)
      end
    else
      # No entity context - RLS will block all access
      @app.call(env)
    end
  end

  private

  def set_rls_context(entity_id)
    # Set PostgreSQL session variable
    # Use LOCAL to ensure it only applies to current transaction
    ActiveRecord::Base.connection.execute(
      "SET LOCAL app.current_entity_id = #{entity_id.to_i}"
    )

    yield
  ensure
    # Reset after request (safety measure)
    begin
      ActiveRecord::Base.connection.execute(
        "RESET app.current_entity_id"
      )
    rescue => e
      # Log but don't fail if reset fails
      Rails.logger.warn "Failed to reset RLS context: #{e.message}"
    end
  end
end
