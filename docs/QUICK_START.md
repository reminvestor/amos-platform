# AMOS Quick Start Guide

## 🚀 Your App is Running!

The AMOS application is successfully running in Docker.

## 🌐 Access the Application

### Main Application
👉 **http://app.localhost:3000**

This is where you:
- Sign up / Sign in
- Chat with AMOS AI
- Create landing pages
- Manage email campaigns
- Configure integrations

### Marketing/Public Site
👉 **http://localhost:3000**

This is the public landing page (no authentication required).

---

## ⚠️ Important: Subdomain Routing

**You MUST use `app.localhost:3000`** to access the application features.

- ✅ `http://app.localhost:3000` - Full app access
- ❌ `http://localhost:3000` - Only public marketing site

This is by design - the app uses subdomain routing to separate the public site from the application.

---

## 🔑 Next Steps to Get Started

### 1. Add AWS Credentials (Required for AI)

Edit the `.env` file:

```bash
AWS_ACCESS_KEY_ID=your_actual_key_here
AWS_SECRET_ACCESS_KEY=your_actual_secret_here
AWS_REGION=us-east-1
```

Without valid AWS Bedrock credentials, the AI won't work!

### 2. Restart the App

After adding credentials:

```bash
docker-compose restart web
```

### 3. Create an Account

1. Visit http://app.localhost:3000
2. Click "Sign up"
3. Create your account
4. Complete onboarding

### 4. Test AMOS

Try these commands in the chat:

- "Create a landing page for my business"
- "Show me my campaigns"
- "Help me create an email campaign"

---

## 📋 What's Working

✅ **Fully Functional:**
- Rails 8 application server
- PostgreSQL database
- Redis cache
- Asset compilation (JS + CSS)
- Authentication system (Devise)
- Chat interface (streaming SSE)
- Landing page creation workflow
- Database migrations applied

⚠️ **Requires Configuration:**
- AWS Bedrock credentials (for AI to work)
- Email campaigns (template linking issue - see PRODUCTION_READINESS.md)
- Optional: Mailgun, Stripe, HubSpot integrations

---

## 🛠️ Useful Commands

### View Logs
```bash
# All services
docker-compose logs -f

# Just the app
docker-compose logs -f web
```

### Rails Console
```bash
docker-compose exec web rails console
```

### Database Operations
```bash
# Run migrations
docker-compose exec web rails db:migrate

# Seed database
docker-compose exec web rails db:seed

# Reset database
docker-compose exec web rails db:reset
```

### Restart Services
```bash
# Restart everything
docker-compose restart

# Restart just the app
docker-compose restart web
```

### Stop Services
```bash
# Stop all
docker-compose down

# Stop and remove all data
docker-compose down -v
```

---

## 🐛 Troubleshooting

### Can't Sign In?

Make sure you're using `app.localhost:3000`, not just `localhost:3000`.

### AI Not Working?

1. Check if AWS credentials are in `.env`
2. Restart: `docker-compose restart web`
3. Check logs: `docker-compose logs -f web`

### Assets Not Loading?

```bash
docker-compose exec web yarn build
docker-compose exec web yarn build:css
```

### Database Issues?

```bash
# Reset database
docker-compose exec web rails db:reset
```

---

## 📚 More Information

- **Complete Docker Guide**: [DOCKER_SETUP.md](DOCKER_SETUP.md)
- **Production Readiness**: [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md)
- **Development Reference**: [CLAUDE.md](CLAUDE.md)
- **Feature Overview**: [README.md](README.md)

---

## 💡 Pro Tips

1. **Bookmark** `http://app.localhost:3000` in your browser
2. **Open DevTools** (F12) to see streaming chat responses in Network tab
3. **Keep logs open** in a terminal: `docker-compose logs -f web`
4. **Use Rails console** for debugging: `docker-compose exec web rails console`

---

## 🎯 What to Test

Once you have AWS credentials configured:

### Landing Pages
1. Chat: "Create a landing page for my consulting business"
2. Follow the conversational prompts
3. AMOS will generate a professional landing page
4. Edit it in the canvas UI

### Email Campaigns
1. Chat: "Create an email campaign"
2. Provide campaign details
3. Note: Template linking has a known issue (see PRODUCTION_READINESS.md)

### Integrations
1. Go to Settings → Integrations
2. Connect Stripe, HubSpot, or Mailgun
3. Chat: "Show my Stripe customers"
4. AMOS will fetch data from your integrations

---

## 📞 Need Help?

- Check logs: `docker-compose logs -f web`
- Rails console: `docker-compose exec web rails console`
- Read docs: [DOCKER_SETUP.md](DOCKER_SETUP.md), [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md)

---

**You're all set! Visit http://app.localhost:3000 and start using AMOS! 🚀**
