# Active Record Encryption Setup

## Overview

The `IntegrationCredential` model uses Rails' built-in Active Record encryption to securely store API credentials. This requires encryption keys to be configured.

## Local Development

For local development, encryption keys are automatically configured in `config/initializers/active_record_encryption.rb` with development-only keys. These are NOT secure for production use.

## Production Setup

### Option 1: Environment Variables

Set these environment variables in your production environment:

```bash
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=<32-character-key>
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=<32-character-key>
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=<32-character-salt>
```

To generate secure keys:
```bash
bin/rails encryption:generate_keys
```

### Option 2: Rails Credentials

Add to your Rails credentials file:

```bash
EDITOR='vim' bin/rails credentials:edit --environment production
```

Add:
```yaml
active_record_encryption:
  primary_key: <32-character-key>
  deterministic_key: <32-character-key>
  key_derivation_salt: <32-character-salt>
```

### Option 3: AWS Secrets Manager (Recommended for ECS)

Run the setup script:
```bash
./aws/create-encryption-secrets.sh
```

Then update your ECS task definition to include these secrets as environment variables.

## Enabling Encryption

Once keys are configured in production:

1. Remove the comment from `app/models/integration_credential.rb`:
   ```ruby
   encrypts :credentials  # Uncomment this line
   ```

2. Deploy the change

3. Run a migration to encrypt existing credentials:
   ```bash
   bin/rails runner 'IntegrationCredential.find_each { |ic| ic.save! }'
   ```

## Verifying Configuration

Check if encryption is properly configured:
```bash
bin/rails encryption:check
```

## Important Notes

- **Never commit encryption keys to version control**
- **Use different keys for each environment**
- **Back up your encryption keys securely**
- **Once data is encrypted, losing the keys means losing the data**
