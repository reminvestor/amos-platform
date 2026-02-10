source "https://rubygems.org"

ruby ">= 3.4.0"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.1"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Bundle and transpile JavaScript [https://github.com/rails/jsbundling-rails]
gem "jsbundling-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Bundle and process CSS [https://github.com/rails/cssbundling-rails]
gem "cssbundling-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Authentication
gem "devise", "~> 4.9"
gem "omniauth-google-oauth2", "~> 1.1"
gem "omniauth-rails_csrf_protection", "~> 1.0"  # CSRF protection for OmniAuth

# Multi-Factor Authentication (MFA)
gem "rotp", "~> 6.3"      # TOTP generation/validation for authenticator apps
gem "rqrcode", "~> 2.2"   # QR code generation for MFA setup

# CORS for API access from mobile apps
gem "rack-cors"

# Background processing
gem "sidekiq", "~> 7.2"

# Environment variables management
gem "dotenv-rails", "~> 3.0"

# Mailgun for email delivery

# AI Integration
gem "ruby-openai", "~> 6.3"
gem "json", "~> 2.7"

gem "mini_magick"


# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
gem "solid_queue_interface"
gem "redis", "~> 5.0"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# JSON Schema validation for DSL
gem "json-schema"

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# Counter caching for document counts
gem "counter_culture", "~> 3.5"

# Vector database support for RAG
gem "neighbor", "~> 0.5"

# AWS SDK for Bedrock integration
gem "aws-sdk-bedrockruntime", "~> 1.0"
gem "aws-sdk-bedrockagent", "~> 1.0"
gem "aws-sdk-bedrockagentruntime", "~> 1.0"
gem "aws-sdk-s3", "~> 1.0"
gem "aws-sdk-polly", "~> 1.0"
gem "aws-sdk-textract", "~> 1.0"
gem "aws-sdk-comprehend", "~> 1.0"
gem "aws-sdk-opensearchservice", "~> 1.0"
gem "aws-sdk-rails", "~> 3.10"
gem "aws-sdk-sesv2"
gem "aws-sdk-sns", "~> 1.0"  # Push notifications via APNs/FCM

# Vector storage and RAG
gem "pinecone", "~> 1.2"

# Solana blockchain integration (lightweight - no native deps)
# We use HTTParty for RPC calls, ed25519 for signatures
gem "ed25519", "~> 1.3"          # Cryptographic signatures
gem "base58", "~> 0.2"           # Base58 encoding for Solana addresses

# HTTP client for API calls (Serper, Solana RPC, etc)
gem "httparty", "~> 0.22.0"

# GitHub API client for AI Pipeline
gem "octokit", "~> 8.0"

# Document parsing
gem "pdf-reader", "~> 2.12"
gem "kramdown", "~> 2.4"

# Document generation (for export features)
gem "prawn", "~> 2.4"           # PDF generation
gem "prawn-table", "~> 0.2"     # Tables in PDFs
gem "caxlsx", "~> 4.1"          # Excel (.xlsx) generation

# Pagination
gem "kaminari", "~> 1.2"

# Social Media APIs
gem "koala", "~> 3.4.0" # Facebook API
gem "instagram_basic_display", "~> 0.2.3" # Instagram Basic Display API
gem "oauth2", "~> 2.0" # OAuth2 for LinkedIn and Twitter APIs
gem "faraday", "~> 2.9" # HTTP client
gem "faraday-multipart", "~> 1.0" # Multipart support for Faraday
gem "faraday-retry", "~> 2.2" # Retry middleware for Faraday v2.0+
gem "csv" # Support for CSV, needed by HTTParty
gem "roo", "~> 2.10" # Excel/spreadsheet parsing (.xlsx, .xls, .ods)
gem "docx", "~> 0.8" # Word document parsing (.docx)

# Markdown rendering
gem "redcarpet"

# HTML parsing for email tracking
gem "nokogiri"

# Headless Chrome for web page capture (screenshots, text extraction)
gem "ferrum", "~> 0.15"

# Scheduled tasks
gem "clockwork"

# Email validation
gem "email_validator"

# Stripe for payments and subscriptions
gem "stripe", "~> 12.0"

# API clients
gem "openai", "~> 0.3.0"
gem "anthropic", "~> 0.1.0"  # Add Anthropic gem for Claude

# Rate limiting and API protection
gem "rack-attack", "~> 6.7"

# Agent Lightning integration for RL-based optimization
#gem "agentlightning", "~> 0.1.0"  # Agent Lightning framework for RL training
gem "opentelemetry-api", "~> 1.3"  # Distributed tracing support
gem "opentelemetry-instrumentation-base", "~> 0.22"  # Base instrumentation framework

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", "~> 7.1.0", require: false

  # Dependency vulnerability scanning [https://github.com/rubysec/bundler-audit]
  gem "bundler-audit", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # ERB template linting
  gem "erb_lint", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Preview emails in browser instead of sending them
  gem "letter_opener", "~> 1.8"
  gem "letter_opener_web", "~> 2.0"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
  # Mocking and stubbing [https://github.com/freerange/mocha]
  gem "mocha"
  # Controller testing helpers (assigns, assert_template)
  gem "rails-controller-testing"
  # Test file generation
  gem "chunky_png", "~> 1.4" # PNG image generation for tests
  # Test coverage reporting
  gem "simplecov", require: false
  gem "simplecov-cobertura", require: false  # For CI coverage reports
  # SQLite for CI/CD testing
  gem "sqlite3", "~> 2.0"
end

gem "down", "~> 5.4"

gem "matrix", "~> 0.4.2"
