class CreateCrawlerConversations < ActiveRecord::Migration[8.0]
  def change
    create_table :crawler_conversations do |t|
      t.references :crawler_job, null: false, foreign_key: true
      t.string :role
      t.text :content
      t.datetime :timestamp

      t.timestamps
    end
  end
end
