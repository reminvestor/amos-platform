# AI-Powered Email Marketing Platform

A modern, AI-enhanced email marketing platform built with Ruby on Rails. This application helps businesses create, manage, and optimize their email marketing campaigns with the power of artificial intelligence.

## Features

### Core Email Marketing
- Create and manage email campaigns
- Design and store email templates
- Manage contact groups and subscribers
- Schedule and automate email campaigns
- Track email performance metrics

### AI Integration
- Generate email content with AI
- Improve existing templates based on performance
- Get AI-powered campaign analysis and insights
- Smart recommendations for campaign optimization

### Analytics & Tracking
- Real-time campaign performance tracking
- Open and click rate monitoring
- Detailed campaign analytics
- AI-driven performance insights

## Tech Stack

- **Backend**: Ruby on Rails 7
- **Frontend**: Bootstrap 5, JavaScript
- **Database**: PostgreSQL
- **Email Service**: AWS SES
- **AI Integration**: OpenAI GPT-4
- **Authentication**: Devise
- **Background Jobs**: Sidekiq

## Prerequisites

- Ruby 3.2.0 or higher
- PostgreSQL 14 or higher
- Redis (for Sidekiq)
- AWS Account (for SES)
- OpenAI API Key

## Environment Variables

Create a `.env` file in the root directory with the following variables:

```bash
# Database
DATABASE_URL=postgresql://localhost/your_database_name

# AWS SES
AWS_ACCESS_KEY_ID=your_aws_access_key
AWS_SECRET_ACCESS_KEY=your_aws_secret_key
AWS_REGION=your_aws_region

# OpenAI
OPENAI_API_KEY=your_openai_api_key

# Redis
REDIS_URL=redis://localhost:6379/1

# Application
RAILS_ENV=development
SECRET_KEY_BASE=your_secret_key_base
```

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/ai-email-marketing.git
   cd ai-email-marketing
   ```

2. Install dependencies:
   ```bash
   bundle install
   ```

3. Setup the database:
   ```bash
   bin/rails db:create db:migrate
   ```

4. Start Redis server (required for Sidekiq):
   ```bash
   redis-server
   ```

5. Start the application:
   ```bash
   bin/rails server
   ```

## Development

- Run tests: `bin/rails test`
- Start Sidekiq: `bundle exec sidekiq`
- Run linter: `bundle exec rubocop`

## Deployment

### Heroku Deployment

1. Create a new Heroku app:
   ```bash
   heroku create your-app-name
   ```

2. Add required buildpacks:
   ```bash
   heroku buildpacks:add heroku/ruby
   heroku buildpacks:add https://github.com/heroku/heroku-buildpack-redis
   ```

3. Configure environment variables:
   ```bash
   heroku config:set RAILS_ENV=production
   heroku config:set SECRET_KEY_BASE=$(bin/rails secret)
   # Add other environment variables as needed
   ```

4. Deploy the application:
   ```bash
   git push heroku main
   ```

5. Run database migrations:
   ```bash
   heroku run bin/rails db:migrate
   ```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- OpenAI for providing the GPT-4 API
- AWS for SES email service
- The Ruby on Rails community
- Bootstrap team for the UI framework
