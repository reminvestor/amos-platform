class AddErrorMessageToEmailDeliveries < ActiveRecord::Migration[8.0]
  def change
    add_column :email_deliveries, :error_message, :text
  end
end
