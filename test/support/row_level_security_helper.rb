# frozen_string_literal: true

module RowLevelSecurityHelper
  # Separate connection class that connects as non-superuser (app_user)
  # PostgreSQL superusers bypass RLS, so we need a regular user to test enforcement
  class RlsConnection < ActiveRecord::Base
    self.abstract_class = true

    def self.establish_rls_connection!
      # Check if we already have our own connection as app_user
      if connection_pool.connected?
        current_user = connection.execute("SELECT current_user").first['current_user']
        return if current_user == 'app_user'

        # Wrong user - disconnect and reconnect
        connection_pool.disconnect!
      end

      db_config = ActiveRecord::Base.connection_db_config.configuration_hash.dup
      establish_connection(
        db_config.merge(
          username: 'app_user',
          password: 'apppassword'
        )
      )
    end
  end

  # Tables to test RLS enforcement on
  RLS_TEST_TABLES = %w[campaigns contacts landing_pages].freeze

  # Ensure RLS is enabled on test tables (idempotent)
  # Must be called via superuser connection before RLS tests run
  def ensure_rls_enabled!
    conn = ActiveRecord::Base.connection

    RLS_TEST_TABLES.each do |table|
      # Check if RLS is already enabled
      result = conn.execute(
        "SELECT relrowsecurity FROM pg_class WHERE relname = '#{table}'"
      )
      next if result.first&.fetch('relrowsecurity', false) == true

      conn.execute("ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY")
      conn.execute("ALTER TABLE #{table} FORCE ROW LEVEL SECURITY")

      # Create policy if it doesn't exist
      policy_exists = conn.execute(
        "SELECT 1 FROM pg_policies WHERE tablename = '#{table}' AND policyname = '#{table}_entity_isolation'"
      ).any?

      unless policy_exists
        conn.execute(<<-SQL)
          CREATE POLICY #{table}_entity_isolation ON #{table}
          FOR ALL
          USING (entity_id = NULLIF(current_setting('app.current_entity_id', true), '')::bigint)
          WITH CHECK (entity_id = NULLIF(current_setting('app.current_entity_id', true), '')::bigint)
        SQL
      end
    end

    # Ensure app_user has permissions on these tables
    RLS_TEST_TABLES.each do |table|
      conn.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON #{table} TO app_user") rescue nil
    end

    # Grant sequence usage for inserts
    conn.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user") rescue nil
  end

  # Get a connection that respects RLS (non-superuser)
  def rls_connection
    RlsConnection.establish_rls_connection!
    RlsConnection.connection
  end

  # Execute a block with a specific entity context for RLS testing
  # Uses a non-superuser connection so RLS policies are enforced
  def with_entity_context(entity)
    entity_id = entity.is_a?(Integer) ? entity : entity.id
    conn = rls_connection

    conn.execute("SET app.current_entity_id = '#{entity_id.to_i}'")
    yield conn
  ensure
    conn&.execute("RESET app.current_entity_id") rescue nil
  end

  # Execute a block without any entity context (should deny all access)
  def without_entity_context
    conn = rls_connection
    conn.execute("RESET app.current_entity_id") rescue nil
    yield conn
  end

  # Execute raw SQL via the RLS connection and return results
  def rls_query(sql)
    rls_connection.execute(sql)
  end

  # Count records visible through RLS
  def rls_count(table, conditions = nil)
    sql = "SELECT COUNT(*) as count FROM #{table}"
    sql += " WHERE #{conditions}" if conditions
    rls_connection.execute(sql).first['count'].to_i
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

  # Get current entity_id from PostgreSQL session (on RLS connection)
  def current_rls_entity_id
    result = rls_connection.execute(
      "SELECT current_setting('app.current_entity_id', true) AS entity_id"
    )
    value = result.first&.fetch('entity_id', nil)
    value.present? ? value.to_i : nil
  end
end
