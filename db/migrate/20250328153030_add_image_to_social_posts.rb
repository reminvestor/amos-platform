class AddImageToSocialPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :social_posts, :image_url, :string
  end
end
