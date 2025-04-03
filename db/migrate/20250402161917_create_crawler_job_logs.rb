class CreateCrawlerJobLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :crawler_job_logs do |t|
      t.references :crawler_job, null: false, foreign_key: true
      t.text :message
      t.string :log_level
      t.datetime :timestamp

      t.timestamps
    end
  end
end
