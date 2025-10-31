class AddUnsubscribeTokenToEmailDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :email_deliveries, :unsubscribe_token, :string
    add_index :email_deliveries, :unsubscribe_token, unique: true

    # Generate tokens for existing records
    reversible do |dir|
      dir.up do
        EmailDelivery.find_each do |delivery|
          delivery.update_column(:unsubscribe_token, SecureRandom.urlsafe_base64(32))
        end
      end
    end
  end
end
