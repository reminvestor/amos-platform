class CreateSocialPostAnalytics < ActiveRecord::Migration[8.0]
  def change
    create_table :social_post_analytics do |t|
      t.references :social_post, null: false, foreign_key: true
      t.integer :likes
      t.integer :comments
      t.integer :shares
      t.integer :views
      t.integer :reach
      t.decimal :engagement_rate
      t.datetime :collected_at

      t.timestamps
    end
  end
end
