# Local Development Guide

## Docker Setup

### Starting the App

```bash
# Start all containers
docker-compose up -d

# View logs
docker-compose logs -f web

# Stop containers
docker-compose down
```

### Accessing the App

**URL**: http://localhost:3000

The app will automatically redirect to the appropriate page based on your authentication status.

## Test Accounts

### Development Login Credentials

**Email**: `admin@test.com`
**Password**: `password123`

**Details**:
- Role: Admin
- Entity: Test Entity Two (automatically created)
- Full access to all features

### Creating Additional Users

You can create additional users via Rails console:

```bash
docker-compose exec web rails console
```

```ruby
# Create a new user
entity = Entity.first_or_create!(name: "My Company")
user = User.create!(
  email: "user@example.com",
  password: "yourpassword",
  password_confirmation: "yourpassword",
  first_name: "First",
  last_name: "Last",
  role: "admin",  # or "marketer" or "viewer"
  entity: entity,
  onboarded: true
)
```

### Available Roles

- `admin` - Full access to all features
- `marketer` - Marketing features access
- `viewer` - Read-only access

## Common URLs

- **Login**: http://localhost:3000/users/sign_in
- **Signup**: http://localhost:3000/users/sign_up
- **Main App**: http://localhost:3000/chat (requires login)
- **Dashboard**: http://localhost:3000 (redirects to /chat when logged in)

## Database Access

### Rails Console

```bash
docker-compose exec web rails console
```

### PostgreSQL Direct Access

```bash
docker-compose exec db psql -U postgres -d agent_marketing_development
```

## Resetting Data

### Reset Database

```bash
docker-compose exec web rails db:reset
```

**Note**: This will wipe all data and reload fixtures. You'll need to create a new user after reset.

### Reload Schema Only

```bash
docker-compose exec web rails db:schema:load
```

## Running Tests

```bash
# All tests
docker-compose exec web rails test

# Specific test file
docker-compose exec web rails test test/models/user_test.rb

# Stripe tests
docker-compose exec web rails test test/controllers/stripe_webhooks_controller_test.rb
```

## Troubleshooting

### Can't Login / "Invalid Email or password"

1. Verify the user exists:
   ```bash
   docker-compose exec web rails runner "puts User.pluck(:email).join(', ')"
   ```

2. Create a fresh user:
   ```bash
   docker-compose exec web rails runner tmp/create_user.rb
   ```

### App Not Loading

1. Check container status:
   ```bash
   docker-compose ps
   ```

2. View Rails logs:
   ```bash
   docker-compose logs web --tail=100
   ```

3. Restart containers:
   ```bash
   docker-compose restart web
   ```

### Database Connection Issues

```bash
# Check DB is running
docker-compose ps db

# Check DB logs
docker-compose logs db --tail=50

# Recreate DB
docker-compose exec web rails db:drop db:create db:migrate
```

## Subscription Testing

The app includes subscription event tracking. To view subscription history:

```bash
docker-compose exec web rails console
```

```ruby
entity = Entity.first
entity.print_subscription_history
entity.subscription_stats
```

See [SUBSCRIPTION_TRACKING.md](SUBSCRIPTION_TRACKING.md) for full details.

## Environment Variables

Key environment variables are in `.env` file:

- `DATABASE_URL` - PostgreSQL connection
- `REDIS_URL` - Redis connection (for caching/jobs)
- `STRIPE_SECRET_KEY` - Stripe API key (for payments)
- `STRIPE_PUBLISHABLE_KEY` - Stripe public key
- `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` - AWS Bedrock (AI)

## Port Mappings

- **3000** - Rails web server
- **5432** - PostgreSQL database
- **6379** - Redis

## Quick Reference

```bash
# Start app
docker-compose up -d

# View logs
docker-compose logs -f

# Rails console
docker-compose exec web rails console

# Run migrations
docker-compose exec web rails db:migrate

# Reset everything
docker-compose down -v && docker-compose up -d
docker-compose exec web rails db:setup
```

## Login Credentials Summary

| Email | Password | Role | Entity |
|-------|----------|------|--------|
| admin@test.com | password123 | admin | Test Entity Two |

**After first login**, you can access:
- Scout AI chat at `/chat`
- All marketing features
- Subscription management
- Full admin capabilities
