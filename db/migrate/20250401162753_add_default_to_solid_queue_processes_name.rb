class AddDefaultToSolidQueueProcessesName < ActiveRecord::Migration[7.1]
  def change
    # First, update any existing null values
    execute <<-SQL
      UPDATE solid_queue_processes#{' '}
      SET name = 'ContactProcessor-' || hostname#{' '}
      WHERE name IS NULL;
    SQL

    # Then modify the column to have a default value
    # Using a simple string default that will be overridden by the application
    change_column_default :solid_queue_processes, :name, from: nil, to: 'ContactProcessor'
  end
end
