class AddAiAnalysisToCampaigns < ActiveRecord::Migration[8.0]
  def change
    add_column :campaigns, :ai_analysis, :text
    add_column :campaigns, :last_analyzed_at, :datetime
  end
end
