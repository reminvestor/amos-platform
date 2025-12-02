class ChangeUserIdNullableOnIntegrationLogs < ActiveRecord::Migration[8.0]
  def change
    change_column_null :integration_logs, :user_id, true
  end
end
