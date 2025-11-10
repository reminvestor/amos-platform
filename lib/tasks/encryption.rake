namespace :encryption do
  desc "Generate Active Record encryption keys"
  task :generate_keys do
    puts "Active Record Encryption Keys:"
    puts "=============================="
    puts "Add these to your environment variables or Rails credentials:"
    puts ""
    puts "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=#{SecureRandom.alphanumeric(32)}"
    puts "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=#{SecureRandom.alphanumeric(32)}"
    puts "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=#{SecureRandom.alphanumeric(32)}"
    puts ""
    puts "For Rails credentials, run:"
    puts "EDITOR='vim' bin/rails credentials:edit"
    puts ""
    puts "And add:"
    puts "active_record_encryption:"
    puts "  primary_key: <generated_key>"
    puts "  deterministic_key: <generated_key>"
    puts "  key_derivation_salt: <generated_salt>"
  end

  desc "Check encryption configuration"
  task check: :environment do
    begin
      # Try to access the encryption config
      primary_key = Rails.application.config.active_record.encryption.primary_key
      deterministic_key = Rails.application.config.active_record.encryption.deterministic_key
      salt = Rails.application.config.active_record.encryption.key_derivation_salt
      
      if primary_key.present? && deterministic_key.present? && salt.present?
        puts "✓ Active Record encryption is configured"
        puts "  Primary key: #{primary_key[0..7]}..." if primary_key
        puts "  Deterministic key: #{deterministic_key[0..7]}..." if deterministic_key
        puts "  Salt: #{salt[0..7]}..." if salt
      else
        puts "✗ Active Record encryption is NOT configured"
        puts "  Run: rake encryption:generate_keys"
      end
    rescue => e
      puts "✗ Error checking encryption: #{e.message}"
    end
  end
end
