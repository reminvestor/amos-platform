class AddSettingsToSocialPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :social_posts, :settings, :jsonb
  end
end
