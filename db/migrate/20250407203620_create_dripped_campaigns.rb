class CreateDrippedCampaigns < ActiveRecord::Migration[8.0]
  def change
    create_table :dripped_campaigns do |t|
      t.references :original_campaign, null: false, foreign_key: { to_table: :campaigns }
      t.references :follow_up_campaign, null: false, foreign_key: { to_table: :campaigns }
      t.integer :delay_days, null: false, default: 3
      t.string :condition
      t.string :condition_value
      t.boolean :active, null: false, default: true
      t.datetime :scheduled_at
      t.integer :sequence_position, null: false, default: 1

      t.timestamps
    end

    add_index :dripped_campaigns, [ :original_campaign_id, :sequence_position ], unique: true, name: 'idx_dripped_campaigns_on_original_campaign_and_position'
  end
end
