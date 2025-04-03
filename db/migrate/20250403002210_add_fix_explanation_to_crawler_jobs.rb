class AddFixExplanationToCrawlerJobs < ActiveRecord::Migration[8.0]
  def change
    add_column :crawler_jobs, :fix_explanation, :text
  end
end
