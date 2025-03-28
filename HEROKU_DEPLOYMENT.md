# Heroku Deployment Guide

This guide covers the steps needed to deploy this application on Heroku with subdomain support.

## Prerequisites

1. A Heroku account
2. Heroku CLI installed locally
3. A custom domain you own (for production use)

## Deployment Steps

### 1. Create a new Heroku app

```bash
heroku create your-app-name
```

### 2. Add PostgreSQL add-on

```bash
heroku addons:create heroku-postgresql:mini
```

### 3. Configure environment variables

```bash
# Set the application host (your custom domain)
heroku config:set APPLICATION_HOST=yourdomain.com

# Set Rails master key (from config/master.key)
heroku config:set RAILS_MASTER_KEY=$(cat config/master.key)

# Set other environment variables as needed
heroku config:set MAILGUN_API_KEY=your-mailgun-api-key
heroku config:set MAILGUN_DOMAIN=your-mailgun-domain
# Add any other API keys or credentials your app needs
```

### 4. Deploy the application

```bash
git push heroku main
```

### 5. Run migrations (should happen automatically via the Procfile)

```bash
heroku run rails db:migrate
```

### 6. Configure custom domain and SSL

```bash
# Add your custom domain to your Heroku app
heroku domains:add yourdomain.com
heroku domains:add www.yourdomain.com
heroku domains:add nuvola.yourdomain.com

# Enable SSL
heroku ssl:auto
```

### 7. DNS Configuration

Update your DNS records with the following:

1. Add a CNAME record for `www` pointing to `your-app-name.herokuapp.com`
2. Add a CNAME record for your apex domain (if supported by your DNS provider) or use ALIAS/ANAME record pointing to `your-app-name.herokuapp.com`
3. Add a CNAME record for `nuvola` pointing to `your-app-name.herokuapp.com`

Example DNS configuration:
```
www.yourdomain.com    CNAME    your-app-name.herokuapp.com
yourdomain.com        ALIAS    your-app-name.herokuapp.com
nuvola.yourdomain.com CNAME    your-app-name.herokuapp.com
```

## Testing Subdomain Setup

After deployment and DNS configuration:

1. Marketing site should be accessible at: `https://yourdomain.com` or `https://www.yourdomain.com`
2. Application with the Nuvola entity should be accessible at: `https://nuvola.yourdomain.com`

## Troubleshooting

### Subdomain Not Working

1. Verify DNS configuration has propagated (can take 24-48 hours)
2. Check Heroku domain settings: `heroku domains`
3. Make sure SSL certificates are provisioned: `heroku ssl`
4. Check for any errors in your application logs: `heroku logs --tail`

### Database Migration Issues

If you encounter issues with the default entity migration:

```bash
# Connect to Heroku's console
heroku run rails console

# Create the default entity manually
entity = Entity.create!(name: "Nuvola Networks", subdomain: "nuvola", slug: "nuvola", status: "active")

# Check if entity was created
Entity.all
```

### SSL Certificate Issues

Heroku's automatic SSL can take some time to provision certificates. If you're having SSL issues:

```bash
# Check the status of your SSL certificates
heroku ssl

# If certificates are failing, try removing and readding the domain
heroku domains:remove problematic-domain.com
heroku domains:add problematic-domain.com
``` 