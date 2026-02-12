# frozen_string_literal: true

module RowLevelSecurityHelper
  # Execute a block with a specific entity context for RLS testing
  def with_entity_context(entity)
    entity_id = entity.is_a?(Integer) ? entity : entity.id

    # Use SET (not SET LOCAL) for tests to ensure it persists through the test
    ActiveRecord::Base.connection.execute(
      "SET app.current_entity_id = '#{entity_id.to_i}'"
    )

    # Clear query cache to ensure subsequent queries use the new setting
    ActiveRecord::Base.connection.clear_query_cache

    yield
  ensure
    ActiveRecord::Base.connection.execute(
      "RESET app.current_entity_id"
    ) rescue nil

    # Clear query cache after reset
    ActiveRecord::Base.connection.clear_query_cache
  end

  # Execute a block without any entity context (should deny all access)
  def without_entity_context
    ActiveRecord::Base.connection.execute(
      "RESET app.current_entity_id"
    ) rescue nil
    yield
  end

  # Verify RLS is enabled on a table
  def rls_enabled?(table_name)
    result = ActiveRecord::Base.connection.execute(
      "SELECT relrowsecurity FROM pg_class WHERE relname = '#{table_name}'"
    )
    result.first&.fetch('relrowsecurity', false) == true
  end

  # Verify RLS policy exists for a table
  def rls_policy_exists?(table_name, policy_name)
    result = ActiveRecord::Base.connection.execute(
      "SELECT 1 FROM pg_policies WHERE tablename = '#{table_name}' AND policyname = '#{policy_name}'"
    )
    result.any?
  end

  # Get current entity_id from PostgreSQL session
  def current_rls_entity_id
    result = ActiveRecord::Base.connection.execute(
      "SELECT current_setting('app.current_entity_id', true) AS entity_id"
    )
    value = result.first&.fetch('entity_id', nil)
    value.present? ? value.to_i : nil
  end
end
