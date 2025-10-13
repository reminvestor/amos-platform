class AddStripeFieldsToEntities < ActiveRecord::Migration[8.0]
  def change
    add_column :entities, :stripe_customer_id, :string
    add_column :entities, :stripe_subscription_id, :string
    add_column :entities, :subscription_status, :string
    add_column :entities, :trial_ends_at, :datetime
    add_column :entities, :current_period_end, :datetime
    add_column :entities, :token_usage, :integer, default: 0
    add_column :entities, :token_limit, :integer
    add_column :entities, :plan_tier, :string

    add_index :entities, :stripe_customer_id
    add_index :entities, :stripe_subscription_id
    add_index :entities, :subscription_status
  end
end
