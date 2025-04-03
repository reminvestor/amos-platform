class CreateCrawlerJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :crawler_jobs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.text :description
      t.text :generated_code
      t.string :status

      t.timestamps
    end
  end
end
