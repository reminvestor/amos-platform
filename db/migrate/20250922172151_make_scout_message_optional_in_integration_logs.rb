class MakeScoutMessageOptionalInIntegrationLogs < ActiveRecord::Migration[8.0]
  def change
    change_column_null :integration_logs, :scout_message_id, true
  end
end