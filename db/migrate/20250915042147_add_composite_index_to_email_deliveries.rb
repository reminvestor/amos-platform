class AddCompositeIndexToEmailDeliveries < ActiveRecord::Migration[8.0]
  def change
    # Add composite index for faster campaign_id lookups with includes
    add_index :email_deliveries, [:campaign_id, :id], name: 'index_email_deliveries_on_campaign_id_and_id'
    
    # Add index for status queries if not exists
    add_index :email_deliveries, :status unless index_exists?(:email_deliveries, :status)
    
    # Add composite index for campaign analytics queries
    add_index :email_deliveries, [:campaign_id, :status], name: 'index_email_deliveries_on_campaign_id_and_status'
  end
end