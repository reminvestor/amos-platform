class CreateSocialPosts < ActiveRecord::Migration[8.0]
  def change
    create_table :social_posts do |t|
      t.string :title
      t.text :content
      t.string :status
      t.datetime :scheduled_at
      t.datetime :published_at
      t.string :platform
      t.string :post_url
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
