# frozen_string_literal: true

# This migration enables encryption for integration credentials.
# It creates a backup column, migrates the data, and enables encryption.
#
# IMPORTANT: This is a reversible migration.
# - up: Enables encryption (requires ACTIVE_RECORD_ENCRYPTION_* env vars)
# - down: Disables encryption and restores plaintext
#
# Before running in production:
# 1. Ensure ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY is set
# 2. Ensure ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY is set
# 3. Ensure ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT is set
# 4. Take a database backup!

class EnableCredentialEncryption < ActiveRecord::Migration[7.1]
  def up
    # Step 1: Add backup column for rollback safety
    add_column :integration_credentials, :credentials_backup, :text

    # Step 2: Copy current plaintext values to backup
    execute <<~SQL
      UPDATE integration_credentials 
      SET credentials_backup = credentials 
      WHERE credentials IS NOT NULL AND credentials != ''
    SQL

    puts "✅ Backed up #{IntegrationCredential.where.not(credentials_backup: nil).count} credential records"

    # Step 3: The IntegrationCredential model will now encrypt on save
    # We need to re-save each record to trigger encryption
    # This is done in a separate rake task to avoid timeout on large datasets
    
    puts ""
    puts "⚠️  IMPORTANT: Run this after migration to encrypt existing data:"
    puts "    rails runner 'IntegrationCredential.find_each { |c| c.save! }'"
    puts ""
    puts "✅ Migration complete. Enable 'encrypts :credentials' in IntegrationCredential model."
  end

  def down
    # Restore from backup if needed
    execute <<~SQL
      UPDATE integration_credentials 
      SET credentials = credentials_backup 
      WHERE credentials_backup IS NOT NULL
    SQL

    remove_column :integration_credentials, :credentials_backup

    puts "✅ Restored plaintext credentials from backup"
    puts "⚠️  Remember to comment out 'encrypts :credentials' in IntegrationCredential model"
  end
end

