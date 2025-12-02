class AddSesFieldsToEmailDeliveries < ActiveRecord::Migration[7.1]
  def change
    add_column :email_deliveries, :ses_message_id, :string
    add_index :email_deliveries, :ses_message_id
    
    # We can eventually remove mailgun columns, but keeping them for now for historical data
    # remove_column :email_deliveries, :mailgun_message_id
    # remove_column :email_deliveries, :mailgun_status
  end
end

