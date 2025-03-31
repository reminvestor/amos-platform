class AddMailgunFieldsToEmailDeliveries < ActiveRecord::Migration[8.0]
  def change
    add_column :email_deliveries, :mailgun_message_id, :string
    add_column :email_deliveries, :mailgun_status, :string
  end
end
