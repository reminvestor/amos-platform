# AMOS Platform Enhancement Plan
**Created**: October 19, 2025
**Analyzed Codebase**: 70,200 lines across 66 models, 30 controllers, 145 services

---

## Executive Summary

This plan outlines strategic enhancements for AMOS, prioritized by **business impact**, **technical feasibility**, and **user value**. The plan is divided into three phases: **Quick Wins** (1-2 weeks each), **Medium-Term** (1-2 months), and **Strategic** (2-6 months).

### Top Priorities
1. **Fix Critical Issues** - Resolve load/clock bugs, add rate limiting, improve error handling
2. **Enhance User Experience** - Add progress indicators, real-time analytics, better feedback
3. **Complete Incomplete Features** - Instagram posting, analytics integration, conversation memory
4. **Strategic Features** - A/B testing, SMS integration, custom workflow builder

---

## Phase 1: Quick Wins (Weeks 1-4)
**Goal**: Stabilize platform, fix critical bugs, improve immediate user experience

### 1.1 Fix Critical Load & Clock Issues ⚡ **URGENT**
**Impact**: High | **Effort**: Medium | **Priority**: P0

**Problem**:
- Git commits 68903fd, d452120 indicate unresolved load issues
- Commit 195330d shows timing/clock problems
- Root cause unclear from commit messages

**Solution**:
```ruby
# Action Items:
1. Add comprehensive logging to identify bottlenecks
   - Log request times in ScoutController
   - Track workflow execution phases
   - Monitor background job queue depths

2. Investigate clock/timing issues
   - Check time zone handling in campaign scheduling
   - Verify scheduled job execution (ProcessCampaignJob)
   - Review ActiveSupport::TimeZone usage

3. Profile slow endpoints
   - Use rack-mini-profiler
   - Identify N+1 queries
   - Check for blocking operations in requests
```

**Files to Review**:
- [app/controllers/scout_controller.rb](app/controllers/scout_controller.rb)
- [app/jobs/process_campaign_job.rb](app/jobs/process_campaign_job.rb)
- [config/application.rb](config/application.rb) (time zone config)

**Success Criteria**:
- Load times < 500ms for 95th percentile
- No missed scheduled campaigns
- Zero unexplained timeout errors

---

### 1.2 Add API Rate Limiting 🛡️
**Impact**: High | **Effort**: Low | **Priority**: P1

**Problem**:
- No rate limiting on Scout chat endpoint
- Integration endpoints vulnerable to abuse
- Could cause service degradation under load

**Solution**:
```ruby
# Gemfile
gem 'rack-attack'

# config/initializers/rack_attack.rb
Rack::Attack.throttle('scout/ip', limit: 50, period: 1.minute) do |req|
  req.ip if req.path == '/scout/chat_stream'
end

Rack::Attack.throttle('integrations/user', limit: 100, period: 1.minute) do |req|
  req.env['warden']&.user&.id if req.path.start_with?('/integrations/')
end
```

**Benefits**:
- Prevents abuse and DoS attacks
- Protects AWS Bedrock API quota
- Improves service reliability

**Success Criteria**:
- Rate limits enforced on all public endpoints
- 429 responses with retry-after headers
- Monitor rate limit hits in logs

---

### 1.3 Fix Contact Model Performance Bug 🐛
**Impact**: Medium | **Effort**: Low | **Priority**: P1

**Problem**:
- `debug_schema` runs on EVERY Contact model load
- Adds 5-10ms overhead per object creation
- Cumulative impact at scale

**Current Code** ([app/models/contact.rb:17](app/models/contact.rb#L17)):
```ruby
Rails.logger.debug "Contact schema columns: #{Contact.column_names.inspect}"
```

**Solution**:
```ruby
# Remove from model entirely, or make conditional:
if ENV['DEBUG_SCHEMA'] == 'true'
  Rails.logger.debug "Contact schema: #{column_names.inspect}"
end
```

**Better Approach**:
```ruby
# Create rake task for schema debugging
# lib/tasks/debug.rake
namespace :debug do
  desc "Debug model schemas"
  task schemas: :environment do
    puts "Contact columns: #{Contact.column_names.inspect}"
    # ... other models
  end
end
```

**Impact**:
- Removes 5-10ms overhead per Contact creation
- Cleaner logs in production
- Better development workflow

---

### 1.4 Improve Error Handling & User Feedback 💬
**Impact**: High | **Effort**: Medium | **Priority**: P1

**Problem**:
- Generic error messages ("I apologize for technical difficulties")
- Users don't understand what went wrong
- No actionable guidance for recovery

**Solution**:

**Step 1: Create Custom Exception Classes**
```ruby
# app/errors/amos_errors.rb
module AmosErrors
  class BedrockError < StandardError
    attr_reader :retry_after, :context

    def initialize(message, retry_after: nil, context: {})
      super(message)
      @retry_after = retry_after
      @context = context
    end
  end

  class IntegrationError < StandardError
    attr_reader :integration_name, :operation

    def initialize(message, integration:, operation: nil)
      super(message)
      @integration_name = integration
      @operation = operation
    end
  end

  class WorkflowError < StandardError
    attr_reader :phase, :execution_id

    def initialize(message, phase:, execution_id:)
      super(message)
      @phase = phase
      @execution_id = execution_id
    end
  end
end
```

**Step 2: Update BedrockService**
```ruby
# app/services/bedrock_service.rb
rescue Aws::BedrockRuntime::Errors::ThrottlingException => e
  raise AmosErrors::BedrockError.new(
    "AI service is currently busy. Please try again in a moment.",
    retry_after: 60,
    context: { request_id: e.request_id }
  )
rescue Aws::BedrockRuntime::Errors::ServiceUnavailableException => e
  raise AmosErrors::BedrockError.new(
    "AI service is temporarily unavailable.",
    retry_after: 120
  )
end
```

**Step 3: Update ScoutController**
```ruby
# app/controllers/scout_controller.rb
rescue AmosErrors::BedrockError => e
  stream_event('error', {
    message: e.message,
    retry_after: e.retry_after,
    type: 'bedrock_error'
  })
rescue AmosErrors::IntegrationError => e
  stream_event('error', {
    message: "#{e.integration_name} integration error: #{e.message}",
    action: "Please check your #{e.integration_name} connection settings.",
    type: 'integration_error'
  })
end
```

**Benefits**:
- Users understand what went wrong
- Actionable recovery guidance
- Better debugging for support
- Improved UX during failures

---

### 1.5 Add Progress Indicators for Long Operations ⏳
**Impact**: High | **Effort**: Medium | **Priority**: P1

**Problem**:
- Landing page generation takes 4-5 minutes with no feedback
- Users don't know if request is processing or stalled
- Timeout set to 600s but no intermediate updates

**Solution**:

**Approach 1: Streaming Progress Events (Recommended)**
```ruby
# app/services/tools/generate_landing_page_tool.rb

def execute(args)
  # Start generation
  stream_progress("Analyzing your requirements...")

  sleep 1
  stream_progress("Generating page structure...")

  # Call AI
  stream_progress("Creating content with AI (this may take 2-3 minutes)...")
  response = bedrock_service.converse(...)

  stream_progress("Compiling final landing page...")
  landing_page = compile_page(response)

  stream_progress("Done! Loading your new landing page...")

  success_response(...)
end

private

def stream_progress(message)
  # Emit SSE event to client
  Rails.logger.info "[LandingPageTool] #{message}"
  # TODO: Emit to SSE stream if available
end
```

**Approach 2: Background Job with Polling**
```ruby
# app/jobs/generate_landing_page_job.rb
class GenerateLandingPageJob < ApplicationJob
  def perform(landing_page_id, user_id)
    landing_page = LandingPage.find(landing_page_id)

    landing_page.update(generation_status: 'analyzing')
    # ... analyze

    landing_page.update(generation_status: 'generating')
    # ... generate

    landing_page.update(generation_status: 'compiling')
    # ... compile

    landing_page.update(generation_status: 'complete')
  end
end

# Client polls: GET /landing_pages/:id/status
```

**Benefits**:
- Users see progress updates
- Can detect stalled jobs
- Better perceived performance
- Reduces support tickets

---

## Phase 2: Medium-Term Enhancements (Weeks 5-12)
**Goal**: Add high-value features, complete incomplete integrations, improve analytics

### 2.1 Real-Time Analytics Dashboard 📊
**Impact**: High | **Effort**: Medium | **Priority**: P1

**Feature Description**:
Live analytics dashboard showing campaign performance, engagement metrics, and real-time activity feed.

**Implementation**:

**Backend: Streaming Analytics API**
```ruby
# app/controllers/analytics_controller.rb
class AnalyticsController < ApplicationController
  include ActionController::Live

  def stream
    response.headers['Content-Type'] = 'text/event-stream'
    sse = SSE.new(response.stream)

    begin
      loop do
        # Fetch latest metrics
        metrics = Analytics::RealtimeService.current_metrics(current_entity)
        sse.write(metrics, event: 'metrics_update')
        sleep 5
      end
    rescue IOError
      # Client disconnected
    ensure
      sse.close
    end
  end
end

# app/services/analytics/realtime_service.rb
class Analytics::RealtimeService
  def self.current_metrics(entity)
    {
      campaigns_active: entity.campaigns.active.count,
      emails_sent_today: EmailDelivery.where(entity: entity, sent_at: Date.today.all_day).count,
      opens_last_hour: EmailDelivery.where(entity: entity, opened_at: 1.hour.ago..).count,
      clicks_last_hour: EmailDelivery.where(entity: entity, clicked_at: 1.hour.ago..).count,
      landing_page_visits_today: LandingPageSubmission.where(entity: entity, created_at: Date.today.all_day).count,
      active_contacts: entity.contacts.where(last_engagement_at: 7.days.ago..).count
    }
  end
end
```

**Frontend: Chart.js Integration**
```javascript
// app/javascript/controllers/analytics_dashboard_controller.js
import { Controller } from "@hotwired/stimulus"
import Chart from 'chart.js/auto'

export default class extends Controller {
  static targets = ["chart"]

  connect() {
    this.initChart()
    this.startStream()
  }

  initChart() {
    this.chart = new Chart(this.chartTarget, {
      type: 'line',
      data: {
        labels: [],
        datasets: [{
          label: 'Opens per Hour',
          data: [],
          borderColor: 'rgb(75, 192, 192)',
        }]
      },
      options: {
        responsive: true,
        animation: { duration: 500 }
      }
    })
  }

  startStream() {
    const eventSource = new EventSource('/analytics/stream')

    eventSource.addEventListener('metrics_update', (e) => {
      const metrics = JSON.parse(e.data)
      this.updateChart(metrics)
    })
  }

  updateChart(metrics) {
    const now = new Date().toLocaleTimeString()
    this.chart.data.labels.push(now)
    this.chart.data.datasets[0].data.push(metrics.opens_last_hour)

    // Keep last 20 data points
    if (this.chart.data.labels.length > 20) {
      this.chart.data.labels.shift()
      this.chart.data.datasets[0].data.shift()
    }

    this.chart.update()
  }
}
```

**UI Components**:
1. **Live Activity Feed** - Recent opens, clicks, submissions
2. **Engagement Heatmap** - Hour-by-hour engagement patterns
3. **Top Performers** - Best campaigns, emails, landing pages
4. **Real-time Alerts** - Spike detection, anomalies

**Benefits**:
- Immediate visibility into campaign performance
- Detect issues in real-time
- Data-driven decision making
- Competitive advantage

---

### 2.2 A/B Testing Framework 🧪
**Impact**: High | **Effort**: High | **Priority**: P1

**Feature Description**:
Built-in A/B testing for email campaigns and landing pages with statistical analysis.

**Database Schema**:
```ruby
# db/migrate/XXXXXX_create_ab_tests.rb
create_table :ab_tests do |t|
  t.references :entity, null: false, foreign_key: true
  t.references :testable, polymorphic: true, null: false
  t.string :name, null: false
  t.string :status, default: 'draft'
  t.jsonb :hypothesis
  t.datetime :started_at
  t.datetime :ended_at
  t.jsonb :results
  t.timestamps
end

create_table :ab_test_variants do |t|
  t.references :ab_test, null: false, foreign_key: true
  t.string :name, null: false
  t.float :traffic_percentage, default: 50.0
  t.jsonb :configuration
  t.integer :impressions, default: 0
  t.integer :conversions, default: 0
  t.float :conversion_rate
  t.timestamps
end

add_index :ab_tests, [:entity_id, :status]
add_index :ab_test_variants, [:ab_test_id, :conversion_rate]
```

**Models**:
```ruby
# app/models/ab_test.rb
class AbTest < ApplicationRecord
  belongs_to :entity
  belongs_to :testable, polymorphic: true
  has_many :variants, class_name: 'AbTestVariant', dependent: :destroy

  enum status: { draft: 'draft', running: 'running', completed: 'completed', stopped: 'stopped' }

  validates :name, presence: true
  validates :variants, length: { minimum: 2, message: "must have at least 2 variants" }

  def start!
    transaction do
      update!(status: 'running', started_at: Time.current)
      variants.each(&:reset_metrics!)
    end
  end

  def calculate_winner
    # Implement statistical significance test (Chi-square)
    variants_data = variants.map { |v| [v.impressions, v.conversions] }

    # Chi-square test for independence
    chi_square = ChiSquareTest.new(variants_data)

    if chi_square.significant?(confidence: 0.95)
      variants.max_by(&:conversion_rate)
    else
      nil # No statistically significant winner
    end
  end
end

# app/models/ab_test_variant.rb
class AbTestVariant < ApplicationRecord
  belongs_to :ab_test

  validates :name, presence: true
  validates :traffic_percentage, numericality: { greater_than: 0, less_than_or_equal to: 100 }

  def record_impression!
    increment!(:impressions)
    update_conversion_rate!
  end

  def record_conversion!
    increment!(:conversions)
    update_conversion_rate!
  end

  private

  def update_conversion_rate!
    return if impressions.zero?
    update_column(:conversion_rate, (conversions.to_f / impressions * 100).round(2))
  end
end
```

**Service Layer**:
```ruby
# app/services/ab_testing/experiment_service.rb
module AbTesting
  class ExperimentService
    def self.select_variant(ab_test, user_identifier)
      # Consistent hashing for stable variant assignment
      hash = Digest::MD5.hexdigest("#{ab_test.id}-#{user_identifier}").to_i(16)
      random_value = (hash % 100).to_f

      cumulative = 0.0
      ab_test.variants.each do |variant|
        cumulative += variant.traffic_percentage
        return variant if random_value < cumulative
      end

      ab_test.variants.last # Fallback
    end

    def self.track_impression(variant)
      variant.record_impression!
    end

    def self.track_conversion(variant)
      variant.record_conversion!
    end
  end
end

# app/services/ab_testing/chi_square_test.rb
module AbTesting
  class ChiSquareTest
    # Implementation of Chi-square test for A/B testing
    def initialize(variant_data)
      @variant_data = variant_data # [[impressions, conversions], ...]
    end

    def significant?(confidence: 0.95)
      chi_square_statistic = calculate_chi_square
      critical_value = critical_value_for_confidence(confidence, degrees_of_freedom)

      chi_square_statistic > critical_value
    end

    private

    def calculate_chi_square
      # Chi-square formula implementation
      # ... statistical calculation
    end

    def degrees_of_freedom
      @variant_data.length - 1
    end

    def critical_value_for_confidence(confidence, df)
      # Chi-square critical values lookup table
      # Or use Statistics gem
    end
  end
end
```

**Integration Example**:
```ruby
# When sending campaign email:
def send_email_with_ab_test(campaign, contact)
  if campaign.ab_test&.running?
    variant = AbTesting::ExperimentService.select_variant(campaign.ab_test, contact.id)
    AbTesting::ExperimentService.track_impression(variant)

    # Use variant configuration
    email_template = variant.configuration['template_id']
    subject_line = variant.configuration['subject']
  else
    # Standard send
  end

  # Send email...

  # Track conversion on click/open
  if email.clicked?
    AbTesting::ExperimentService.track_conversion(variant)
  end
end
```

**Benefits**:
- Data-driven campaign optimization
- Automated winner selection
- Statistical significance calculation
- Improved conversion rates

---

### 2.3 Conversation Memory & Context 🧠
**Impact**: High | **Effort**: Medium | **Priority**: P1

**Problem**:
- Scout chat doesn't remember previous conversations
- Users have to re-explain context every session
- No learning from past interactions

**Solution**:

**Database Schema**:
```ruby
# db/migrate/XXXXXX_create_conversation_memories.rb
create_table :conversation_memories do |t|
  t.references :entity, null: false, foreign_key: true
  t.references :user, null: false, foreign_key: true
  t.string :memory_type # 'preference', 'fact', 'goal', 'context'
  t.text :content
  t.jsonb :metadata
  t.float :relevance_score, default: 1.0
  t.datetime :last_accessed_at
  t.integer :access_count, default: 0
  t.timestamps
end

add_index :conversation_memories, [:entity_id, :user_id, :memory_type]
add_index :conversation_memories, :relevance_score
```

**Memory Service**:
```ruby
# app/services/conversation/memory_service.rb
module Conversation
  class MemoryService
    def initialize(entity, user)
      @entity = entity
      @user = user
    end

    def store_memory(content, type:, metadata: {})
      ConversationMemory.create!(
        entity: @entity,
        user: @user,
        memory_type: type,
        content: content,
        metadata: metadata,
        relevance_score: 1.0
      )
    end

    def recall_memories(query: nil, type: nil, limit: 10)
      memories = ConversationMemory.where(entity: @entity, user: @user)
      memories = memories.where(memory_type: type) if type

      if query
        # Use vector similarity search if available
        memories = memories.where("content ILIKE ?", "%#{query}%")
      end

      memories.order(relevance_score: :desc, last_accessed_at: :desc)
              .limit(limit)
              .tap { |results| mark_accessed(results) }
    end

    def extract_and_store_from_conversation(conversation_text)
      # Use AI to extract important information
      prompt = <<~PROMPT
        Extract important facts, preferences, and goals from this conversation:

        #{conversation_text}

        Return as JSON array:
        [
          {"type": "preference", "content": "User prefers email campaigns on Mondays"},
          {"type": "fact", "content": "Company sells dental products"},
          {"type": "goal", "content": "Increase email open rates by 20%"}
        ]
      PROMPT

      response = BedrockService.instance.converse(...)
      memories_data = JSON.parse(response)

      memories_data.each do |mem|
        store_memory(mem['content'], type: mem['type'])
      end
    end

    def decay_old_memories
      # Reduce relevance score of old, unused memories
      ConversationMemory.where(entity: @entity, user: @user)
                       .where('last_accessed_at < ?', 30.days.ago)
                       .update_all('relevance_score = relevance_score * 0.9')
    end

    private

    def mark_accessed(memories)
      memory_ids = memories.map(&:id)
      ConversationMemory.where(id: memory_ids)
                       .update_all('access_count = access_count + 1, last_accessed_at = NOW()')
    end
  end
end
```

**Integration with ScoutController**:
```ruby
# app/controllers/scout_controller.rb
def chat_stream
  # Load relevant memories
  memory_service = Conversation::MemoryService.new(current_entity, current_user)
  relevant_memories = memory_service.recall_memories(query: message, limit: 5)

  # Include in AI context
  context = {
    user_message: message,
    memories: relevant_memories.map { |m| "#{m.memory_type}: #{m.content}" }.join("\n")
  }

  # After conversation, extract new memories
  memory_service.extract_and_store_from_conversation(full_conversation)
end
```

**Benefits**:
- Personalized AI interactions
- Users don't repeat themselves
- AI learns preferences over time
- Better context for recommendations

---

### 2.4 Fix Instagram Integration 📸
**Impact**: Medium | **Effort**: Medium | **Priority**: P2

**Problem**:
- Instagram Basic Display API doesn't support posting
- TODO comment in code indicates incomplete implementation
- Users can't publish to Instagram

**Solution**:

**Update Instagram Service**:
```ruby
# app/services/social_media/instagram_service.rb
class SocialMedia::InstagramService < SocialMedia::BaseService
  # Use Facebook Graph API for Instagram Business accounts

  def publish_post(content:, image_url: nil, hashtags: [])
    validate_business_account!

    # Step 1: Upload media to Instagram container
    container_id = create_media_container(image_url, content, hashtags)

    # Step 2: Publish container
    publish_container(container_id)
  end

  private

  def create_media_container(image_url, caption, hashtags)
    full_caption = "#{caption}\n\n#{hashtags.map { |tag| "##{tag}" }.join(' ')}"

    response = HTTParty.post(
      "https://graph.facebook.com/v18.0/#{instagram_business_account_id}/media",
      body: {
        image_url: image_url,
        caption: full_caption,
        access_token: @connection.access_token
      }
    )

    handle_response(response)['id']
  end

  def publish_container(container_id)
    response = HTTParty.post(
      "https://graph.facebook.com/v18.0/#{instagram_business_account_id}/media_publish",
      body: {
        creation_id: container_id,
        access_token: @connection.access_token
      }
    )

    handle_response(response)
  end

  def validate_business_account!
    unless @connection.metadata['instagram_business_account_id']
      raise SocialMedia::ConfigurationError.new(
        "Instagram posting requires a Business account connected via Facebook."
      )
    end
  end

  def instagram_business_account_id
    @connection.metadata['instagram_business_account_id']
  end
end
```

**Connection Setup Flow**:
```ruby
# Add OAuth flow for Facebook connection with Instagram permissions
# app/controllers/connections_controller.rb

def instagram_oauth_callback
  # Exchange code for token
  token_response = exchange_oauth_code(params[:code])

  # Get Instagram Business account ID
  fb_response = HTTParty.get(
    "https://graph.facebook.com/v18.0/me/accounts",
    query: { access_token: token_response['access_token'] }
  )

  # For each Facebook Page, check for linked Instagram account
  instagram_account = find_instagram_business_account(fb_response['data'], token_response['access_token'])

  # Store connection with Instagram account ID
  Connection.create!(
    entity: current_entity,
    integration: Integration.find_by(slug: 'instagram'),
    access_token: encrypt(token_response['access_token']),
    metadata: {
      instagram_business_account_id: instagram_account['id'],
      facebook_page_id: instagram_account['page_id']
    }
  )
end
```

**Benefits**:
- Complete Instagram posting functionality
- Removes TODO/incomplete code
- Enables multi-platform social campaigns

---

### 2.5 SMS Integration (Twilio) 📱
**Impact**: Medium | **Effort**: Low | **Priority**: P2

**Feature Description**:
Add SMS as a campaign channel alongside email, enabling multi-channel marketing.

**Database Schema**:
```ruby
# db/migrate/XXXXXX_create_sms_campaigns.rb
create_table :sms_campaigns do |t|
  t.references :entity, null: false, foreign_key: true
  t.string :name, null: false
  t.text :message_body, null: false
  t.string :from_number
  t.string :status, default: 'draft'
  t.integer :total_recipients, default: 0
  t.integer :delivered_count, default: 0
  t.integer :failed_count, default: 0
  t.datetime :scheduled_at
  t.timestamps
end

create_table :sms_deliveries do |t|
  t.references :sms_campaign, null: false, foreign_key: true
  t.references :contact, null: false, foreign_key: true
  t.string :to_number, null: false
  t.string :twilio_sid
  t.string :status # 'queued', 'sent', 'delivered', 'failed'
  t.text :error_message
  t.datetime :delivered_at
  t.timestamps
end

add_index :sms_deliveries, [:sms_campaign_id, :status]
```

**Integration Setup**:
```ruby
# Create Twilio integration in seeds
Integration.find_or_create_by!(slug: 'twilio') do |i|
  i.name = 'Twilio'
  i.description = 'SMS messaging platform'
  i.logo_url = 'https://...'
  i.auth_type = 'api_key'
  i.config = {
    base_url: 'https://api.twilio.com/2010-04-01',
    required_credentials: ['account_sid', 'auth_token', 'from_number']
  }
end
```

**SMS Service**:
```ruby
# app/services/sms_service.rb
class SmsService
  def initialize(entity)
    @entity = entity
    @connection = Connection.find_by(entity: entity, integration: Integration.find_by(slug: 'twilio'))
  end

  def send_message(to:, body:, campaign: nil)
    validate_connection!

    client = Twilio::REST::Client.new(account_sid, auth_token)

    message = client.messages.create(
      from: from_number,
      to: to,
      body: body
    )

    # Record delivery
    if campaign
      SmsDelivery.create!(
        sms_campaign: campaign,
        contact: Contact.find_by(phone: to),
        to_number: to,
        twilio_sid: message.sid,
        status: 'sent'
      )
    end

    message
  rescue Twilio::REST::RestError => e
    Rails.logger.error "[SmsService] Twilio error: #{e.message}"

    if campaign
      SmsDelivery.create!(
        sms_campaign: campaign,
        to_number: to,
        status: 'failed',
        error_message: e.message
      )
    end

    raise
  end

  def handle_webhook(params)
    # Handle Twilio delivery status callbacks
    delivery = SmsDelivery.find_by(twilio_sid: params['MessageSid'])
    return unless delivery

    delivery.update!(
      status: params['MessageStatus'],
      delivered_at: Time.current
    )
  end

  private

  def validate_connection!
    raise "Twilio not connected" unless @connection
  end

  def account_sid
    @connection.credentials['account_sid']
  end

  def auth_token
    @connection.credentials['auth_token']
  end

  def from_number
    @connection.credentials['from_number']
  end
end
```

**Background Job**:
```ruby
# app/jobs/process_sms_campaign_job.rb
class ProcessSmsCampaignJob < ApplicationJob
  queue_as :default

  def perform(sms_campaign_id)
    campaign = SmsCampaign.find(sms_campaign_id)
    campaign.update!(status: 'sending')

    sms_service = SmsService.new(campaign.entity)

    # Get recipients (contacts with phone numbers)
    recipients = campaign.entity.contacts.where.not(phone: nil)
    campaign.update!(total_recipients: recipients.count)

    recipients.find_each do |contact|
      begin
        # Personalize message
        message = personalize_message(campaign.message_body, contact)

        # Send SMS
        sms_service.send_message(
          to: contact.phone,
          body: message,
          campaign: campaign
        )

        campaign.increment!(:delivered_count)

        # Rate limiting (Twilio allows ~1/sec on trial)
        sleep 1
      rescue => e
        Rails.logger.error "[ProcessSmsCampaignJob] Failed to send to #{contact.phone}: #{e.message}"
        campaign.increment!(:failed_count)
      end
    end

    campaign.update!(status: 'completed')
  end

  private

  def personalize_message(template, contact)
    template.gsub('{{first_name}}', contact.first_name || 'there')
            .gsub('{{last_name}}', contact.last_name || '')
            .gsub('{{company}}', contact.company || '')
  end
end
```

**Benefits**:
- Multi-channel marketing (email + SMS)
- Higher engagement rates
- Direct mobile reach
- Competitive feature parity

---

## Phase 3: Strategic Enhancements (Months 3-6)
**Goal**: Build competitive advantages, enable advanced workflows, scale platform

### 3.1 Custom Workflow Builder UI 🎨
**Impact**: Very High | **Effort**: Very High | **Priority**: P1

**Feature Description**:
Visual drag-and-drop editor for creating custom workflow templates without writing YAML.

**Architecture**:

**Frontend: React Flow Integration**
```javascript
// app/javascript/components/WorkflowBuilder.jsx
import React, { useState, useCallback } from 'react'
import ReactFlow, {
  MiniMap,
  Controls,
  Background,
  useNodesState,
  useEdgesState,
  addEdge,
} from 'reactflow'
import 'reactflow/dist/style.css'

const nodeTypes = {
  gatherContext: GatherContextNode,
  executeGoal: ExecuteGoalNode,
  validation: ValidationNode,
  tool: ToolNode,
  condition: ConditionNode
}

export default function WorkflowBuilder({ initialWorkflow }) {
  const [nodes, setNodes, onNodesChange] = useNodesState(initialWorkflow?.nodes || [])
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialWorkflow?.edges || [])

  const onConnect = useCallback(
    (params) => setEdges((eds) => addEdge(params, eds)),
    [setEdges]
  )

  const onSave = async () => {
    // Convert flow to YAML template
    const template = convertFlowToYaml(nodes, edges)

    const response = await fetch('/workflow_templates', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ template })
    })

    if (response.ok) {
      alert('Workflow saved!')
    }
  }

  return (
    <div style={{ width: '100vw', height: '100vh' }}>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={onConnect}
        nodeTypes={nodeTypes}
      >
        <Controls />
        <MiniMap />
        <Background variant="dots" gap={12} size={1} />
      </ReactFlow>

      <div style={{ position: 'absolute', top: 20, right: 20 }}>
        <button onClick={onSave} className="btn btn-primary">
          Save Workflow
        </button>
      </div>
    </div>
  )
}

function convertFlowToYaml(nodes, edges) {
  // Convert React Flow graph to YAML template structure
  const template = {
    template_version: 2,
    name: 'Custom Workflow',
    description: 'User-created workflow',
    keywords: [],
    phases: []
  }

  // Process nodes by phase type
  nodes.forEach(node => {
    if (node.type === 'gatherContext') {
      template.phases.push({
        name: 'gather_context',
        description: node.data.description,
        prompts: node.data.prompts
      })
    }
    // ... handle other node types
  })

  return YAML.stringify(template)
}
```

**Node Components**:
```javascript
// app/javascript/components/nodes/GatherContextNode.jsx
function GatherContextNode({ data, id }) {
  return (
    <div className="workflow-node gather-context">
      <div className="node-header">Gather Context</div>
      <Handle type="target" position="top" />

      <div className="node-content">
        <input
          type="text"
          placeholder="Description"
          value={data.description}
          onChange={(e) => data.onChange(id, 'description', e.target.value)}
        />

        <textarea
          placeholder="Prompts (one per line)"
          value={data.prompts?.join('\n')}
          onChange={(e) => data.onChange(id, 'prompts', e.target.value.split('\n'))}
        />
      </div>

      <Handle type="source" position="bottom" />
    </div>
  )
}
```

**Backend: Template Management**
```ruby
# app/controllers/workflow_templates_controller.rb
class WorkflowTemplatesController < ApplicationController
  def create
    # Save custom template to entity-specific location
    template_path = Rails.root.join('app', 'workflow_templates', 'custom', "#{params[:name]}.yml")

    File.write(template_path, params[:template])

    # Reload workflow engine to pick up new template
    WorkflowEngine.reload_templates!

    render json: { success: true }
  end

  def index
    # List all templates (built-in + custom)
    templates = Dir[Rails.root.join('app', 'workflow_templates', '**', '*.yml')]

    parsed_templates = templates.map do |path|
      YAML.load_file(path).merge(path: path)
    end

    render json: parsed_templates
  end
end
```

**Benefits**:
- No-code workflow creation
- Empowers non-technical users
- Faster iteration on workflows
- Competitive differentiation
- Reduces support burden

---

### 3.2 Advanced Audience Segmentation 🎯
**Impact**: High | **Effort**: Medium | **Priority**: P2

**Feature Description**:
Boolean logic builder for complex audience targeting with behavioral triggers.

**Implementation**:

**Database Schema**:
```ruby
# db/migrate/XXXXXX_add_advanced_segmentation.rb
create_table :audience_segments do |t|
  t.references :entity, null: false, foreign_key: true
  t.string :name, null: false
  t.text :description
  t.jsonb :rules # Store boolean logic tree
  t.integer :contacts_count, default: 0
  t.datetime :last_calculated_at
  t.timestamps
end

# Example rules JSON:
# {
#   "operator": "AND",
#   "conditions": [
#     {
#       "field": "last_engagement_at",
#       "operator": ">=",
#       "value": "7.days.ago"
#     },
#     {
#       "operator": "OR",
#       "conditions": [
#         { "field": "tags", "operator": "includes", "value": "vip" },
#         { "field": "lifetime_value", "operator": ">", "value": 1000 }
#       ]
#     }
#   ]
# }
```

**Segmentation Service**:
```ruby
# app/services/segmentation/query_builder.rb
module Segmentation
  class QueryBuilder
    def self.build_query(segment)
      base_query = Contact.where(entity: segment.entity)
      apply_rules(base_query, segment.rules)
    end

    def self.apply_rules(query, rules)
      operator = rules['operator'] # AND, OR
      conditions = rules['conditions']

      if operator == 'AND'
        conditions.reduce(query) { |q, condition| apply_condition(q, condition, :and) }
      elsif operator == 'OR'
        or_query = conditions.map { |condition| apply_condition(Contact.all, condition, :or) }
        query.where(id: or_query.map(&:pluck).flatten.uniq)
      end
    end

    def self.apply_condition(query, condition, join_type)
      if condition['field']
        # Leaf node - actual condition
        field = condition['field']
        operator = condition['operator']
        value = parse_value(condition['value'])

        case operator
        when '='
          query.where(field => value)
        when '>'
          query.where("#{field} > ?", value)
        when '<'
          query.where("#{field} < ?", value)
        when '>='
          query.where("#{field} >= ?", value)
        when 'includes'
          query.where("#{field} @> ?", [value].to_json) # JSONB contains
        when 'not_includes'
          query.where.not("#{field} @> ?", [value].to_json)
        end
      else
        # Nested rules
        apply_rules(query, condition)
      end
    end

    def self.parse_value(value)
      # Handle dynamic values like "7.days.ago"
      if value.match?(/(\d+)\.(days|weeks|months)\.ago/)
        eval(value)
      else
        value
      end
    end
  end
end
```

**UI: Segment Builder**
```javascript
// app/javascript/components/SegmentBuilder.jsx
import React, { useState } from 'react'

export default function SegmentBuilder({ onSave }) {
  const [rules, setRules] = useState({
    operator: 'AND',
    conditions: []
  })

  const addCondition = () => {
    setRules({
      ...rules,
      conditions: [
        ...rules.conditions,
        { field: '', operator: '=', value: '' }
      ]
    })
  }

  const addGroup = () => {
    setRules({
      ...rules,
      conditions: [
        ...rules.conditions,
        { operator: 'AND', conditions: [] }
      ]
    })
  }

  return (
    <div className="segment-builder">
      <div className="operator-selector">
        <select value={rules.operator} onChange={(e) => setRules({ ...rules, operator: e.target.value })}>
          <option value="AND">Match ALL conditions</option>
          <option value="OR">Match ANY condition</option>
        </select>
      </div>

      <div className="conditions">
        {rules.conditions.map((condition, index) => (
          <ConditionRow
            key={index}
            condition={condition}
            onChange={(updated) => updateCondition(index, updated)}
          />
        ))}
      </div>

      <div className="actions">
        <button onClick={addCondition}>+ Add Condition</button>
        <button onClick={addGroup}>+ Add Group</button>
      </div>

      <button onClick={() => onSave(rules)} className="btn btn-primary">
        Save Segment
      </button>
    </div>
  )
}

function ConditionRow({ condition, onChange }) {
  const fields = [
    { value: 'last_engagement_at', label: 'Last Engagement' },
    { value: 'created_at', label: 'Contact Since' },
    { value: 'tags', label: 'Tags' },
    { value: 'metadata.lifetime_value', label: 'Lifetime Value' },
  ]

  return (
    <div className="condition-row">
      <select value={condition.field} onChange={(e) => onChange({ ...condition, field: e.target.value })}>
        <option value="">Select field...</option>
        {fields.map(f => <option key={f.value} value={f.value}>{f.label}</option>)}
      </select>

      <select value={condition.operator} onChange={(e) => onChange({ ...condition, operator: e.target.value })}>
        <option value="=">equals</option>
        <option value=">">greater than</option>
        <option value="<">less than</option>
        <option value="includes">includes</option>
      </select>

      <input
        type="text"
        value={condition.value}
        onChange={(e) => onChange({ ...condition, value: e.target.value })}
        placeholder="Value"
      />
    </div>
  )
}
```

**Behavioral Triggers**:
```ruby
# app/models/behavioral_trigger.rb
class BehavioralTrigger < ApplicationRecord
  belongs_to :entity
  belongs_to :campaign

  # trigger_type: 'email_opened', 'link_clicked', 'landing_page_visited', 'product_purchased'
  # action: 'add_to_campaign', 'send_email', 'update_tag', 'webhook'

  def self.process_event(event_type, contact, metadata = {})
    triggers = where(trigger_type: event_type, entity: contact.entity, active: true)

    triggers.each do |trigger|
      if trigger.matches_conditions?(contact, metadata)
        trigger.execute_action(contact)
      end
    end
  end

  def matches_conditions?(contact, metadata)
    # Evaluate conditions stored in JSONB
    return true if conditions.blank?

    Segmentation::QueryBuilder.apply_rules(
      Contact.where(id: contact.id),
      conditions
    ).exists?
  end

  def execute_action(contact)
    case action
    when 'add_to_campaign'
      campaign.contact_groups.first.contacts << contact
    when 'send_email'
      # Send immediate email
      CampaignService.send_email_to_contact(campaign, contact)
    when 'update_tag'
      contact.tags << action_params['tag']
      contact.save!
    when 'webhook'
      # Trigger webhook
      WebhookService.deliver(action_params['webhook_url'], contact.to_json)
    end
  end
end
```

**Benefits**:
- Precise audience targeting
- Automated behavioral campaigns
- Higher conversion rates
- Advanced marketing capabilities

---

### 3.3 API Documentation & Developer Portal 📚
**Impact**: Medium | **Effort**: Medium | **Priority**: P2

**Feature Description**:
OpenAPI/Swagger documentation with developer portal, API key management, and webhook setup.

**Implementation**:

**Install rswag gem**:
```ruby
# Gemfile
gem 'rswag'
gem 'rswag-api'
gem 'rswag-ui'

# Run generator
rails g rswag:install
```

**API Spec**:
```ruby
# spec/requests/api/v1/campaigns_spec.rb
require 'swagger_helper'

RSpec.describe 'API V1 Campaigns', type: :request do
  path '/api/v1/campaigns' do
    get 'List campaigns' do
      tags 'Campaigns'
      produces 'application/json'
      security [api_key: []]

      parameter name: :page, in: :query, type: :integer, required: false
      parameter name: :per_page, in: :query, type: :integer, required: false

      response '200', 'campaigns found' do
        schema type: :object,
          properties: {
            campaigns: {
              type: :array,
              items: {
                type: :object,
                properties: {
                  id: { type: :integer },
                  name: { type: :string },
                  status: { type: :string },
                  created_at: { type: :string, format: 'date-time' }
                }
              }
            },
            meta: {
              type: :object,
              properties: {
                total: { type: :integer },
                page: { type: :integer },
                per_page: { type: :integer }
              }
            }
          }

        run_test!
      end

      response '401', 'unauthorized' do
        run_test!
      end
    end

    post 'Create campaign' do
      tags 'Campaigns'
      consumes 'application/json'
      security [api_key: []]

      parameter name: :campaign, in: :body, schema: {
        type: :object,
        properties: {
          name: { type: :string },
          subject: { type: :string },
          body: { type: :string },
          from_email: { type: :string }
        },
        required: ['name', 'subject', 'body']
      }

      response '201', 'campaign created' do
        run_test!
      end
    end
  end
end
```

**API Key Management**:
```ruby
# db/migrate/XXXXXX_create_api_keys.rb
create_table :api_keys do |t|
  t.references :entity, null: false, foreign_key: true
  t.string :name, null: false
  t.string :key_hash, null: false
  t.string :key_prefix, null: false # First 8 chars for identification
  t.datetime :last_used_at
  t.integer :requests_count, default: 0
  t.jsonb :permissions, default: {}
  t.datetime :expires_at
  t.timestamps
end

add_index :api_keys, :key_hash, unique: true
add_index :api_keys, :key_prefix

# app/models/api_key.rb
class ApiKey < ApplicationRecord
  belongs_to :entity

  before_create :generate_key

  def self.authenticate(key)
    key_hash = Digest::SHA256.hexdigest(key)
    api_key = find_by(key_hash: key_hash)

    return nil unless api_key
    return nil if api_key.expired?

    api_key.touch(:last_used_at)
    api_key.increment!(:requests_count)

    api_key
  end

  def expired?
    expires_at && expires_at < Time.current
  end

  private

  def generate_key
    raw_key = SecureRandom.hex(32)
    self.key_hash = Digest::SHA256.hexdigest(raw_key)
    self.key_prefix = raw_key[0..7]

    # Return raw key ONLY once, never stored
    @generated_key = raw_key
  end

  attr_reader :generated_key
end
```

**Authentication Middleware**:
```ruby
# app/controllers/api/v1/base_controller.rb
module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_api_key

      private

      def authenticate_api_key
        key = request.headers['X-API-Key']

        unless key
          render json: { error: 'API key required' }, status: :unauthorized
          return
        end

        @api_key = ApiKey.authenticate(key)

        unless @api_key
          render json: { error: 'Invalid API key' }, status: :unauthorized
          return
        end

        @current_entity = @api_key.entity
      end

      attr_reader :current_entity, :api_key
    end
  end
end
```

**Developer Portal UI**:
```erb
<!-- app/views/developer_portal/index.html.erb -->
<div class="developer-portal">
  <h1>AMOS API Documentation</h1>

  <div class="api-keys-section">
    <h2>Your API Keys</h2>

    <%= form_with url: api_keys_path, method: :post do |f| %>
      <%= f.text_field :name, placeholder: 'Key name' %>
      <%= f.submit 'Generate API Key', class: 'btn btn-primary' %>
    <% end %>

    <table class="table">
      <thead>
        <tr>
          <th>Name</th>
          <th>Prefix</th>
          <th>Created</th>
          <th>Last Used</th>
          <th>Requests</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <% @api_keys.each do |key| %>
          <tr>
            <td><%= key.name %></td>
            <td><code><%= key.key_prefix %>...</code></td>
            <td><%= key.created_at.to_date %></td>
            <td><%= key.last_used_at&.to_date || 'Never' %></td>
            <td><%= number_with_delimiter(key.requests_count) %></td>
            <td>
              <%= button_to 'Revoke', api_key_path(key), method: :delete, class: 'btn btn-sm btn-danger' %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>

  <div class="swagger-ui-section">
    <h2>API Reference</h2>
    <iframe src="/api-docs" style="width: 100%; height: 800px; border: 1px solid #ddd;"></iframe>
  </div>
</div>
```

**Benefits**:
- Third-party integrations
- Developer ecosystem
- API-first product strategy
- Self-service documentation
- Reduced support burden

---

## Phase 4: Performance & Scalability (Ongoing)

### 4.1 Database Optimization
**Impact**: High | **Effort**: Medium | **Priority**: P1

**Actions**:
1. **Add Missing Indexes**
   ```ruby
   add_index :affiliate_clicks, [:affiliate_id, :landed_at]
   add_index :email_deliveries, [:campaign_id, :status, :sent_at]
   add_index :workflow_contexts, [:workflow_execution_id, :phase]
   ```

2. **Implement Database Partitioning** (for large datasets)
   ```sql
   -- Partition email_deliveries by sent_at month
   CREATE TABLE email_deliveries_2025_10 PARTITION OF email_deliveries
   FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
   ```

3. **Add Read Replicas** (for analytics queries)
   ```ruby
   # config/database.yml
   production:
     primary:
       <<: *default
       database: amos_production

     replica:
       <<: *default
       database: amos_production
       host: replica.database.host
       replica: true
   ```

4. **Archive Old Data**
   ```ruby
   # app/jobs/archive_old_campaigns_job.rb
   class ArchiveOldCampaignsJob < ApplicationJob
     def perform
       # Move campaigns older than 1 year to cold storage
       old_campaigns = Campaign.where('created_at < ?', 1.year.ago)

       old_campaigns.find_each do |campaign|
         ArchiveService.store(campaign)
         campaign.destroy
       end
     end
   end
   ```

---

### 4.2 Caching Strategy
**Impact**: High | **Effort**: Low | **Priority**: P1

**Implementation**:
```ruby
# Cache tool catalog
class ToolCatalog
  def all_tools
    Rails.cache.fetch('tool_catalog/all_tools', expires_in: 1.hour) do
      discover_tools
    end
  end
end

# Cache workflow templates
class WorkflowEngine
  def load_template(name)
    Rails.cache.fetch("workflow_template/#{name}", expires_in: 10.minutes) do
      YAML.load_file(template_path(name))
    end
  end
end

# Cache integration schemas
class IntegrationApiService
  def fetch_schema(integration)
    Rails.cache.fetch("integration_schema/#{integration.id}", expires_in: 1.day) do
      http_client.get("#{integration.base_url}/schema")
    end
  end
end

# Fragment caching for dashboard
<!-- app/views/dashboard/index.html.erb -->
<% cache ['dashboard', current_entity, Date.today], expires_in: 5.minutes do %>
  <%= render 'metrics_summary' %>
<% end %>
```

---

### 4.3 Background Job Optimization
**Impact**: Medium | **Effort**: Low | **Priority**: P2

**Actions**:
1. **Split Queues by Priority**
   ```ruby
   # config/solid_queue.yml
   queues:
     - name: critical
       processes: 10
       polling_interval: 1
     - name: default
       processes: 5
       polling_interval: 5
     - name: low_priority
       processes: 2
       polling_interval: 10
   ```

2. **Add Job Deduplication**
   ```ruby
   class ProcessCampaignJob < ApplicationJob
     include SolidQueue::Deduplication

     deduplicate by: ->(campaign_id) { "campaign:#{campaign_id}" }
     deduplicate within: 5.minutes

     def perform(campaign_id)
       # ...
     end
   end
   ```

3. **Implement Job Monitoring**
   ```ruby
   # app/jobs/monitor_stalled_jobs.rb
   class MonitorStalledJobsJob < ApplicationJob
     def perform
       stalled_jobs = SolidQueue::Job.where('started_at < ? AND finished_at IS NULL', 30.minutes.ago)

       stalled_jobs.each do |job|
         Rails.logger.error "[MonitorStalledJobs] Job #{job.id} stalled: #{job.job_class}"
         # Alert operations team
       end
     end
   end
   ```

---

## Testing Strategy

### Priority Test Coverage

**P0 (Critical - Write Immediately):**
1. Agent workflow execution tests
2. API authentication & authorization
3. Rate limiting tests
4. Error handling & recovery

**P1 (High - Write with Feature):**
1. A/B testing statistical calculations
2. Conversation memory storage/retrieval
3. SMS delivery & webhooks
4. Segmentation query builder

**P2 (Medium - Write Eventually):**
1. Workflow builder UI interactions
2. Advanced segmentation edge cases
3. API documentation accuracy
4. Performance benchmarks

**Example Test**:
```ruby
# test/services/conversation/memory_service_test.rb
require 'test_helper'

class Conversation::MemoryServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @service = Conversation::MemoryService.new(@entity, @user)
  end

  test "stores and recalls memories" do
    @service.store_memory("User prefers Mondays", type: 'preference')

    memories = @service.recall_memories(type: 'preference')

    assert_equal 1, memories.count
    assert_equal "User prefers Mondays", memories.first.content
  end

  test "decays old unused memories" do
    memory = @service.store_memory("Old fact", type: 'fact')
    memory.update(last_accessed_at: 60.days.ago, relevance_score: 1.0)

    @service.decay_old_memories

    memory.reload
    assert_operator memory.relevance_score, :<, 1.0
  end
end
```

---

## Risk Assessment & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **Load/clock issues persist** | High | High | Comprehensive logging, profiling, dedicated debugging sprint |
| **Bedrock API quotas exceeded** | Medium | High | Implement request throttling, caching, fallback to OpenAI |
| **Instagram API changes** | Medium | Medium | Monitor Meta changelog, implement graceful degradation |
| **Database performance degrades** | Medium | High | Proactive indexing, query monitoring, read replicas |
| **A/B test calculations incorrect** | Low | High | Peer review statistics, add test coverage, use proven library |
| **SMS costs spiral** | Medium | Medium | Implement spend limits, per-entity quotas, alerts |
| **API abuse** | Medium | Medium | Rate limiting (already planned), API key rotation, monitoring |
| **Workflow builder too complex** | High | Medium | Start with simple MVP, user testing, iterate based on feedback |

---

## Success Metrics

### Phase 1 (Quick Wins)
- ✅ Load times < 500ms for 95th percentile
- ✅ Zero critical errors in production for 7 days
- ✅ Rate limiting blocks 100% of abuse attempts
- ✅ Error messages include actionable guidance (measured via support tickets down 30%)

### Phase 2 (Medium-Term)
- ✅ Real-time analytics dashboard has < 2s latency
- ✅ A/B tests run with 95% statistical confidence
- ✅ Conversation memory reduces repeat questions by 40%
- ✅ Instagram posts publish successfully 99% of the time
- ✅ SMS campaigns achieve 95%+ delivery rate

### Phase 3 (Strategic)
- ✅ 50% of users create custom workflows within 3 months
- ✅ Advanced segmentation increases campaign conversion by 25%
- ✅ API generates 1000+ requests/day from third-party integrations
- ✅ Workflow builder rated 4.5+ stars by users

---

## Resource Requirements

### Development Team
- **Phase 1 (Weeks 1-4)**: 1 full-stack developer
- **Phase 2 (Weeks 5-12)**: 2 full-stack developers
- **Phase 3 (Months 3-6)**: 2-3 full-stack + 1 frontend specialist

### Infrastructure
- **Immediate**: Add monitoring (Sentry/Honeybadger), rate limiting (Rack::Attack)
- **Month 2**: Add Redis cluster for caching, read replica for analytics
- **Month 4**: Scale background job workers, consider CDN for assets

### Third-Party Services
- **Twilio**: $0.0075/SMS (estimate $500/month for 60K messages)
- **Sentry**: $26/month (Developer plan)
- **Redis Cloud**: $15-50/month depending on dataset size

---

## Conclusion

This enhancement plan transforms AMOS from a **solid marketing automation platform** into a **best-in-class AI-powered marketing suite** with:

1. **Stability & Reliability** - Fixed critical bugs, comprehensive error handling, monitoring
2. **Advanced Features** - A/B testing, real-time analytics, conversation memory, SMS
3. **User Empowerment** - Custom workflow builder, advanced segmentation, no-code tools
4. **Developer Ecosystem** - API documentation, webhooks, third-party integrations
5. **Scalability** - Optimized database, caching, job queues for 10x growth

**Recommended Start**: Begin with Phase 1 quick wins to stabilize the platform, then parallel-track Phase 2 features (analytics + A/B testing) while planning Phase 3 strategic initiatives.

**Estimated Timeline**: 6 months from start to full strategic feature completion, with quick wins delivered in first month.

**Expected Outcomes**:
- 30% reduction in support tickets (better errors, documentation)
- 25% increase in user retention (better UX, more features)
- 40% increase in campaign conversion (A/B testing, segmentation)
- 10x scalability headroom (performance optimizations)

---

**Next Steps**: Review this plan, prioritize based on business goals, and begin Phase 1 implementation.
