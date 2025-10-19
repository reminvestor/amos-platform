#!/bin/bash

# Get database URL from Secrets Manager
DB_URL=$(aws secretsmanager get-secret-value --secret-id agent-marketing-database-url --query SecretString --output text)

# Parse the connection details
DB_HOST=$(echo $DB_URL | sed 's|.*@\([^:]*\):[0-9]*/.*|\1|')
DB_NAME=$(echo $DB_URL | sed 's|.*/\([^?]*\).*|\1|')
DB_USER="postgres"

# Extract and decode the password
DB_PASS_ENCODED=$(echo $DB_URL | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')
DB_PASS=$(python3 -c "import urllib.parse; print(urllib.parse.unquote('$DB_PASS_ENCODED'))")

echo "Restoring database from ~/Downloads/latest.dump"
echo "Target: $DB_HOST/$DB_NAME"

# Restore the database
PGPASSWORD="$DB_PASS" pg_restore \
  --host=$DB_HOST \
  --port=5432 \
  --username=$DB_USER \
  --dbname=$DB_NAME \
  --no-owner \
  --no-privileges \
  --clean \
  --if-exists \
  --verbose \
  ~/Downloads/latest.dump

echo "Database restore completed!"
