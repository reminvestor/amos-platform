class CreateCampaignGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :campaign_groups do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :contact_group, null: false, foreign_key: true

      t.timestamps
    end
  end
end
