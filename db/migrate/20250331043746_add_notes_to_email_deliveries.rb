class AddNotesToEmailDeliveries < ActiveRecord::Migration[8.0]
  def change
    add_column :email_deliveries, :notes, :text
  end
end
