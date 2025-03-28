class CreateSocialMediaAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :social_media_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :platform
      t.string :status
      t.string :username
      t.string :profile_url
      t.string :access_token
      t.string :refresh_token
      t.datetime :token_expires_at
      t.jsonb :settings

      t.timestamps
    end
  end
end
