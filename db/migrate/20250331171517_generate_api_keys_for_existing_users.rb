class GenerateApiKeysForExistingUsers < ActiveRecord::Migration[7.1]
  def up
    # Generate API keys for users who don't have one
    User.where(api_key: nil).find_each do |user|
      user.update_column(:api_key, SecureRandom.hex(32))
      puts "Generated API key for user: #{user.email}"
    end
  end

  def down
    # No need to revert this migration
    # If we need to remove API keys, we can create a separate migration
  end
end
