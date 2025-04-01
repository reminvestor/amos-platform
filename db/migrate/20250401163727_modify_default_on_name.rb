class ModifyDefaultOnName < ActiveRecord::Migration[7.1]
  def change
    # First, update any existing null values with a UUID
    execute <<-SQL
      UPDATE solid_queue_processes 
      SET name = 'ContactProcessor-' || gen_random_uuid()::text
      WHERE name IS NULL;
    SQL

    # Then modify the column to have a default value using UUID
    execute <<-SQL
      ALTER TABLE solid_queue_processes 
      ALTER COLUMN name SET DEFAULT 'ContactProcessor-' || gen_random_uuid()::text;
    SQL
  end
end 