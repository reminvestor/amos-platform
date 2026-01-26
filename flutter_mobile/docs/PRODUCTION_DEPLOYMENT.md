# Production Deployment Guide

This guide covers deploying both the Rails API (AWS) and Flutter mobile app (App Store) for production.

---

## Part 1: Rails API on AWS

### 1.1 API Requirements for Mobile

The mobile app needs these endpoints to be accessible:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/auth/login` | POST | User login (returns api_key) |
| `/api/auth/logout` | POST | Logout |
| `/api/auth/me` | GET | Check auth status |
| `/api/mfa/verify` | POST | MFA verification |
| `/amos/chat_stream` | POST | SSE chat endpoint |
| `/amos/new_session` | POST | Create chat session |
| `/amos/upload_files` | POST | File uploads |
| `/api/v1/*` | * | All v1 API endpoints |

### 1.2 No CORS Needed for Mobile

Unlike web browsers, mobile apps make direct HTTP requests and don't require CORS headers. Your existing API should work without changes.

### 1.3 AWS Infrastructure Checklist

- [ ] **Load Balancer**: ALB with HTTPS (SSL certificate via ACM)
- [ ] **Domain**: Configure DNS (e.g., `api.amoslabs.com`)
- [ ] **Security Group**: Allow inbound 443 (HTTPS) from anywhere
- [ ] **RDS**: PostgreSQL database (private subnet)
- [ ] **Redis**: ElastiCache for caching (private subnet)
- [ ] **S3**: For file uploads and RAG documents
- [ ] **Secrets Manager**: Store API keys and credentials

### 1.4 Environment Variables for Production

Create production environment on AWS (ECS/Elastic Beanstalk/EC2):

```bash
# Required for Rails
RAILS_ENV=production
SECRET_KEY_BASE=<generate with: rails secret>
DATABASE_URL=postgres://user:pass@rds-endpoint:5432/amos_production
REDIS_URL=redis://elasticache-endpoint:6379/0

# AWS Services
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=<from IAM role preferably>
AWS_SECRET_ACCESS_KEY=<from IAM role preferably>

# Bedrock AI
BEDROCK_DEFAULT_MODEL=claude-sonnet-4-5

# OAuth (for Gmail/Outlook integration)
GMAIL_CLIENT_ID=<from Google Cloud Console>
GMAIL_CLIENT_SECRET=<secret>
OUTLOOK_CLIENT_ID=<from Azure Portal>
OUTLOOK_CLIENT_SECRET=<secret>
APP_URL=https://api.amoslabs.com

# Other services as needed...
```

### 1.5 SSL/HTTPS Configuration

**Mobile apps require HTTPS in production.** iOS will block HTTP connections.

Options:
1. **AWS Certificate Manager (ACM)** - Free SSL certs for use with ALB
2. **Let's Encrypt** - Free, auto-renewing certs (if using EC2 directly)

### 1.6 Health Check Endpoint

Ensure you have a health check endpoint for the load balancer:

```ruby
# config/routes.rb
get '/health', to: proc { [200, {}, ['OK']] }
```

---

## Part 2: Mobile App Configuration

### 2.1 Production API URL

The mobile app needs to know your production API URL.

Create `.env.production` in `flutter_mobile/`:

```bash
# flutter_mobile/.env.production
API_BASE_URL=https://api.amoslabs.com
```

### 2.2 Build with Production URL

When building for release:

```bash
flutter build ios --release \
  --dart-define=API_BASE_URL=https://api.amoslabs.com \
  --dart-define=IS_PRODUCTION=true
```

Or use the deploy script:

```bash
API_BASE_URL=https://api.amoslabs.com ./deploy-ios.sh --testflight
```

### 2.3 iOS App Transport Security

iOS blocks insecure connections by default. Your `Info.plist` should NOT allow arbitrary loads in production:

```xml
<!-- ios/Runner/Info.plist -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
</dict>
```

This is already the default - no changes needed if using HTTPS.

---

## Part 3: OAuth Configuration for Production

### 3.1 Gmail OAuth

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Navigate to **APIs & Services → OAuth consent screen**
3. Click **Publish App** (moves from Testing to Production)
4. Update redirect URIs:
   - Add: `https://api.amoslabs.com/oauth/callback`
   - Keep localhost for development
5. If using sensitive scopes, submit for Google verification

### 3.2 Outlook OAuth

1. Go to [Azure Portal](https://portal.azure.com/)
2. Navigate to **App registrations → Your app**
3. Update redirect URIs:
   - Add: `https://api.amoslabs.com/oauth/callback`
4. Under **Authentication**, ensure "Accounts in any organizational directory" is selected

### 3.3 Update OAuth Configurations in Rails

```ruby
# Run in production Rails console
OauthConfiguration.find_by(integration: Integration.find_by(slug: 'gmail')).update!(
  redirect_uri: 'https://api.amoslabs.com/oauth/callback'
)

OauthConfiguration.find_by(integration: Integration.find_by(slug: 'outlook')).update!(
  redirect_uri: 'https://api.amoslabs.com/oauth/callback'
)
```

Or set via environment variable - the initializer reads `APP_URL`:

```bash
APP_URL=https://api.amoslabs.com
```

---

## Part 4: Deployment Checklist

### Before First Release

- [ ] AWS infrastructure provisioned and running
- [ ] Domain configured with SSL certificate
- [ ] Production environment variables set
- [ ] Database migrations run (`rails db:migrate`)
- [ ] Seeds run if needed (`rails db:seed`)
- [ ] OAuth redirect URIs updated for production
- [ ] Health check endpoint verified
- [ ] API endpoints tested from external network

### Mobile App

- [ ] Apple Developer account enrolled
- [ ] App Store Connect app created
- [ ] Certificates and provisioning profiles created
- [ ] App icons and screenshots prepared
- [ ] Privacy policy and support URLs set
- [ ] `.env.production` created with production API URL
- [ ] Test build on physical device
- [ ] TestFlight beta test successful

### Final Steps

- [ ] Submit to App Store Review
- [ ] Monitor crash reports after release
- [ ] Set up alerting for API errors

---

## Part 5: AWS Architecture Diagram

```
                    ┌─────────────────┐
                    │   Route 53      │
                    │ api.amoslabs.com│
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  CloudFront     │
                    │  (Optional CDN) │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │      ALB        │
                    │  (HTTPS:443)    │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────▼───┐  ┌───────▼────┐  ┌──────▼─────┐
     │  ECS Task  │  │  ECS Task  │  │  ECS Task  │
     │   Rails    │  │   Rails    │  │ SolidQueue │
     └──────┬─────┘  └─────┬──────┘  └──────┬─────┘
            │              │                │
            └──────────────┼────────────────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
     ┌────────▼───┐  ┌─────▼────┐  ┌───▼────┐
     │    RDS     │  │   Redis  │  │   S3   │
     │ PostgreSQL │  │ElastiCache│  │ Files  │
     └────────────┘  └──────────┘  └────────┘
```

---

## Part 6: Quick Start Commands

### Deploy API to AWS (using Docker)

```bash
# Build and push Docker image
docker build -t amos-api .
docker tag amos-api:latest <aws-account>.dkr.ecr.us-east-1.amazonaws.com/amos-api:latest
aws ecr get-login-password | docker login --username AWS --password-stdin <aws-account>.dkr.ecr.us-east-1.amazonaws.com
docker push <aws-account>.dkr.ecr.us-east-1.amazonaws.com/amos-api:latest

# Update ECS service
aws ecs update-service --cluster amos-cluster --service amos-api --force-new-deployment
```

### Deploy Mobile to TestFlight

```bash
cd flutter_mobile
API_BASE_URL=https://api.amoslabs.com ./deploy-ios.sh --testflight
```

### Deploy Mobile to App Store

```bash
cd flutter_mobile
API_BASE_URL=https://api.amoslabs.com ./deploy-ios.sh --release
```

---

## Troubleshooting

### Mobile app can't connect to API

1. **Check API is reachable**: `curl https://api.amoslabs.com/health`
2. **Check SSL certificate**: `openssl s_client -connect api.amoslabs.com:443`
3. **Check security group**: Ensure port 443 is open
4. **Check logs**: Look at Rails logs for connection attempts

### OAuth redirect fails

1. **Check redirect URI matches exactly** (including trailing slashes)
2. **Check OAuth credentials** are set in production environment
3. **Check APP_URL** is set correctly

### App rejected by Apple

1. **Read rejection reason carefully**
2. **Common fixes**: Add demo credentials, fix crashes, update screenshots
3. **Resubmit** after fixing issues
