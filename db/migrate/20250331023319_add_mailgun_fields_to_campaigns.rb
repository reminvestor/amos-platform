class AddMailgunFieldsToCampaigns < ActiveRecord::Migration[8.0]
  def change
    add_column :campaigns, :mailgun_tag, :string
    add_column :campaigns, :mailgun_stats, :jsonb
  end
end
