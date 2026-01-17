# Active Record Encryption Configuration
# This sets up encryption keys for development
# For production, use environment variables or Rails credentials

Rails.application.configure do
  if Rails.env.development? || Rails.env.test?
    # Generate deterministic keys for development/test
    # These are NOT secure for production use
    config.active_record.encryption.primary_key = 'EGY8WhulUOXixybod7ZWwMIL68R9o5kC'
    config.active_record.encryption.deterministic_key = 'aPA5XyALhf75NNnMzaspW7akTfZp0lPY'
    config.active_record.encryption.key_derivation_salt = 'xEY0dt6TZcAMg52K7O84wYzkjvbA62Hz'
  else
    # For production, use environment variables
    config.active_record.encryption.primary_key = ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY']
    config.active_record.encryption.deterministic_key = ENV['ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY']
    config.active_record.encryption.key_derivation_salt = ENV['ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT']
  end
  
  # MIGRATION PHASE: Allow reading both encrypted and unencrypted data
  # This enables a gradual migration from plaintext to encrypted
  # Once all data is encrypted, this can be set to false
  # 
  # SECURITY NOTE: Set this to false after running:
  #   rails runner 'IntegrationCredential.find_each(&:save!)'
  #
  config.active_record.encryption.support_unencrypted_data = true
end
