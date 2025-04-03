class AddErrorMessageToCrawlerJobs < ActiveRecord::Migration[8.0]
  def change
    add_column :crawler_jobs, :error_message, :text
  end
end
