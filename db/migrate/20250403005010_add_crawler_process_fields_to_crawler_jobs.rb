class AddCrawlerProcessFieldsToCrawlerJobs < ActiveRecord::Migration[8.0]
  def change
    add_column :crawler_jobs, :conversation_stage, :string
    add_column :crawler_jobs, :target_urls, :text
    add_column :crawler_jobs, :test_results, :text
    add_column :crawler_jobs, :improvement_attempts, :integer
  end
end
