class EnableRowLevelSecurity < ActiveRecord::Migration[8.0]
  def up
    # Create helper function to get current entity ID from session
    execute <<-SQL
      CREATE OR REPLACE FUNCTION current_entity_id()
      RETURNS BIGINT AS $$
      BEGIN
        RETURN NULLIF(current_setting('app.current_entity_id', TRUE), '')::BIGINT;
      EXCEPTION
        WHEN OTHERS THEN
          RETURN NULL;
      END;
      $$ LANGUAGE plpgsql STABLE;
    SQL

    # Get all tables with entity_id column
    tables_with_entity_id = ActiveRecord::Base.connection.tables.select do |table|
      next if table == 'schema_migrations' || table == 'ar_internal_metadata'

      columns = ActiveRecord::Base.connection.columns(table).map(&:name)
      columns.include?('entity_id')
    end

    puts "\n=== Enabling RLS on #{tables_with_entity_id.count} tables ==="

    # Enable RLS and create policies for each table
    tables_with_entity_id.each do |table_name|
      puts "  ✓ Enabling RLS on: #{table_name}"

      # Enable RLS on the table
      execute "ALTER TABLE #{table_name} ENABLE ROW LEVEL SECURITY;"

      # Create policy: Users can only see rows where entity_id matches their current entity
      # Policy name format: {table}_entity_isolation_policy
      policy_name = "#{table_name}_entity_isolation_policy"

      execute <<-SQL
        CREATE POLICY #{policy_name}
        ON #{table_name}
        FOR ALL
        TO PUBLIC
        USING (
          entity_id = current_entity_id()
          OR current_entity_id() IS NULL  -- Allow superuser/admin access
        );
      SQL
    end

    puts "=== RLS enabled on #{tables_with_entity_id.count} tables ===\n"

    # Add helpful comment
    execute <<-SQL
      COMMENT ON FUNCTION current_entity_id() IS
      'Returns the current entity ID from session variable app.current_entity_id.
       Used by RLS policies to enforce multi-tenant data isolation.
       Set via: SET LOCAL app.current_entity_id = <entity_id>;';
    SQL
  end

  def down
    # Get all tables with entity_id column
    tables_with_entity_id = ActiveRecord::Base.connection.tables.select do |table|
      next if table == 'schema_migrations' || table == 'ar_internal_metadata'

      columns = ActiveRecord::Base.connection.columns(table).map(&:name)
      columns.include?('entity_id')
    end

    puts "\n=== Disabling RLS on #{tables_with_entity_id.count} tables ==="

    # Drop policies and disable RLS
    tables_with_entity_id.each do |table_name|
      puts "  ✓ Disabling RLS on: #{table_name}"

      policy_name = "#{table_name}_entity_isolation_policy"

      # Drop policy
      execute "DROP POLICY IF EXISTS #{policy_name} ON #{table_name};"

      # Disable RLS
      execute "ALTER TABLE #{table_name} DISABLE ROW LEVEL SECURITY;"
    end

    # Drop helper function
    execute "DROP FUNCTION IF EXISTS current_entity_id();"

    puts "=== RLS disabled on #{tables_with_entity_id.count} tables ===\n"
  end
end
