# AMOS - Automated Management Operating System

> **AI-Powered Business Automation Platform**  
> Natural language workflows, intelligent automation, seamless integrations

---

## 🚀 What is AMOS?

**AMOS** is an AI-first business automation platform where you accomplish complex tasks through natural conversation. No forms to fill out. No complicated workflows to configure. Just tell AMOS what you need, and it intelligently orchestrates the work.

### The Vision

AMOS transforms business automation from:
- ❌ **Manual form-filling** → ✅ **Natural conversation**
- ❌ **Rigid workflows** → ✅ **Intelligent adaptation**
- ❌ **Repetitive data entry** → ✅ **Context-aware automation**
- ❌ **Technical complexity** → ✅ **Simple requests**

---

## ✨ Core Capabilities

### 🤖 Conversational AI Interface
- **Natural Language Processing**: Understand complex requests in plain English
- **Context-Aware**: Remembers previous conversations, uploaded files, and business profile
- **Intelligent Workflows**: Automatically selects and executes multi-step processes
- **Real-Time Streaming**: See progress as AMOS works
- **Voice Ready**: Upcoming support for hands-free voice commands

### 🌐 Universal Integration Platform
- **Connect Anything**: Stripe, HubSpot, Mailgun, and any REST API
- **Cross-Platform Workflows**: Orchestrate tasks across multiple services automatically
- **Intelligent Data Sync**: Move customer data, sync contacts, update records
- **No-Code Integration Builder**: Users add custom APIs through UI
- **Secure & Compliant**: Encrypted credentials, OAuth 2.0, audit logging

**Power Example:** Say *"Email my Stripe customers who upgraded this week"* and AMOS:
1. Fetches customers from Stripe API
2. Filters by upgrade event
3. Generates personalized emails
4. Sends via Mailgun
5. Updates HubSpot contact records
All in one conversation! 🚀

### 📋 Workflow Template System (V2)
AMOS uses **intelligent, phase-based workflows** that:
- **Gather Context Intelligently**: Checks conversation history, uploaded files, and business profile before asking questions
- **Execute Goals Adaptively**: AI plans the best approach using available tools
- **Validate Results**: Ensures quality and completeness automatically
- **Self-Heal**: Attempts to fix issues when they occur

**Available Templates:**
- 📄 **Landing Page Creation** - Create professional, conversion-optimized landing pages
- 📧 **Email Campaigns** - Build and manage email campaigns with templates
- 🎯 **Add Groups to Campaigns** - Associate contact groups with campaigns
- 🔄 **[Extensible]** - Add custom templates as YAML files

### 🛠️ Powerful Tool Ecosystem

**20+ AI-Accessible Tools:**
- **Data Management**: Create, read, update campaigns, contacts, landing pages, templates
- **Content Generation**: AI-powered landing pages, email content
- **Analytics**: Campaign performance, customer insights, usage tracking
- **Integrations**: Connect Stripe, HubSpot, Mailgun, and any REST API
- **Workflow**: Context management, template discovery, task planning

### 🔌 Cross-Platform Integration (Key Differentiator!)

**AMOS doesn't just manage your marketing - it connects your entire business:**

- **Pull data from anywhere**: Stripe customers, HubSpot deals, Google Analytics
- **Push data everywhere**: Create HubSpot contacts from Stripe, sync email engagement
- **Orchestrate workflows**: Multi-step automation across multiple platforms
- **No coding required**: Connect, configure, and let AMOS handle the rest

**Example:** *"Email my Stripe customers who haven't opened my last campaign"*
- Fetches Stripe customer list
- Cross-references with campaign data
- Generates personalized emails
- Sends via Mailgun
- Updates engagement in HubSpot

### 📊 Smart Context Management
- **WorkflowContext**: Persistent data across workflow phases
- **File Uploads**: Analyze PDFs, images, brand guidelines
- **Conversation Memory**: Reference previous discussions
- **Entity Profiles**: Business information readily available

---

## 🎯 What Can You Do With AMOS?

### Cross-Platform Automation (🔥 Most Powerful)

```
You: "Email my new Stripe customers from this week"
AMOS: 🔧 Fetching Stripe customers from the last 7 days...
      📊 Found 12 new customers
      🔧 Creating personalized welcome emails...
      ✅ 12 emails sent via Mailgun!
      
      Emails include their subscription details and next steps.
```

```
You: "Sync my campaign email clicks to HubSpot"
AMOS: 🔧 Analyzing campaign engagement...
      📊 342 contacts clicked links
      🔧 Updating HubSpot contact records...
      ✅ Synced engagement data!
      
      HubSpot now shows email engagement for all contacts.
      Ready for your sales team to follow up! 🎯
```

### Marketing & Campaigns
```
You: "Create an email campaign for our spring sale"
AMOS: [Gathers details conversationally]
      [Creates email template]
      [Sets up campaign]
      ✅ "Campaign created! Ready to send to 1,234 contacts."
```

### Landing Pages
```
You: "Build a landing page for our new product"
AMOS: [Asks about value proposition, target audience, CTA]
      [Generates professional Bootstrap HTML]
      ✅ "Landing page live! Preview: [link]"
```

### Contact Management
```
You: "Add my VIP customers to the holiday campaign"
AMOS: [Finds contact group and campaign]
      [Associates them]
      ✅ "Done! 45 VIP customers added to holiday campaign."
```

### Analytics & Insights
```
You: "How's my Q4 campaign performing?"
AMOS: [Analyzes campaign data]
      [Generates visualization]
      ✅ "28% open rate, 12% click rate. Top performing with millennials."
```

---

## 🏗️ Architecture

### V2 Workflow System

```
┌─────────────────────────────────────────────────────────────┐
│                    User Request (Chat)                       │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                   PlannerAgentService                        │
│  • Analyzes request intent                                   │
│  • Finds matching workflow template                          │
│  • Creates execution plan                                    │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    WorkflowEngine (V2)                       │
│  Executes 3-Phase Workflow:                                  │
│                                                              │
│  Phase 1: GatherContextExecutor                              │
│    ├─ Check conversation history                             │
│    ├─ Check uploaded files                                   │
│    ├─ Check business profile                                 │
│    └─ Ask conversationally for missing data                  │
│                                                              │
│  Phase 2: GoalExecutor                                       │
│    ├─ Structured: Use data mapping (reliable)                │
│    ├─ Adaptive: AI plans tool sequence (flexible)            │
│    └─ Execute tools with gathered context                    │
│                                                              │
│  Phase 3: ValidationExecutor                                 │
│    ├─ Validate outputs                                       │
│    ├─ Run quality checks                                     │
│    └─ Attempt auto-fixes if needed                           │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                      Success Message                         │
│  "✅ Task complete! Here's what I created..."                │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

**Services:**
- `ScoutController` - Main chat interface and streaming
- `PlannerAgentService` - Intelligent workflow planning
- `WorkflowEngine` - Orchestrates phase execution
- `BedrockService` - AWS Bedrock Claude integration
- `Tools::ToolCatalog` - 20+ AI-accessible tools

**Phase Executors:**
- `GatherContextExecutor` - Intelligent data collection
- `GoalExecutor` - Adaptive or structured goal execution  
- `ValidationExecutor` - Quality assurance and auto-fixing

**Models:**
- `WorkflowExecution` - Tracks workflow runs
- `WorkflowContext` - Persistent phase data
- `TaskSession` - User task state management
- `Campaign`, `Contact`, `LandingPage`, etc. - Business entities

---

## 🚦 Getting Started

### Prerequisites
- Ruby 3.4+
- Rails 8.0+
- PostgreSQL 14+
- AWS Account (for Bedrock Claude)
- Node.js & Yarn

### Installation

```bash
# Clone the repository
git clone [repository-url]
cd agent_marketing

# Install dependencies
bundle install
yarn install

# Setup database
rails db:create db:migrate db:seed

# Configure environment
cp .env.example .env
# Add your AWS credentials and other keys

# Start the server
bin/dev
```

### Demo Login Credentials

After running `db:seed`, you can log in with these demo accounts:

| Email | Password | Role |
|-------|----------|------|
| admin@demo.com | password123 | Admin (full access) |
| marketer@demo.com | password123 | Marketer (marketing features) |
| viewer@demo.com | password123 | Viewer (read-only) |

**Troubleshooting Login Issues:**

If you can't log in, passwords may have been reset. Run:

```bash
# Show current login credentials
rails dev:show_logins

# Reset all demo user passwords to 'password123'
rails dev:reset_passwords

# Or do a full database reset
rails dev:full_reset
```

**Docker Users:** Logins are automatically created on container startup.

**IMPORTANT:** `docker compose restart` does NOT re-run seeds. To ensure seeds run:

```bash
# Full container recreation (runs db:seed)
docker compose down && docker compose up -d

# Quick password reset (if containers already running)
docker compose exec web rails dev:reset_passwords

# Or manually run seeds
docker compose exec web rails db:seed
```

### Environment Variables

```bash
# AWS Bedrock (Required)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret

# Database
DATABASE_URL=postgresql://localhost/amos_development

# Optional
MAILGUN_API_KEY=your_key
REDIS_URL=redis://localhost:6379
```

---

## 📖 Usage Guide

### Basic Interaction

1. **Open AMOS** - Navigate to the workspace
2. **Start Chatting** - Type what you want to do
3. **AMOS Responds** - Asks clarifying questions if needed
4. **Workflow Executes** - See real-time progress
5. **Results Delivered** - Get links, previews, and data

### Example Conversations

**Create a Landing Page:**
```
You: Create a landing page for my coaching program

AMOS: Great! Let's create that landing page. I need a few details:
      • What's your program name?
      • What's your main value proposition?
      • Who's your target audience?
      • What action should visitors take?

You: It's called "Executive Leadership Accelerator"
     We help C-suite executives become better leaders
     Target audience is Fortune 500 executives
     They should schedule a free consultation

AMOS: 🔧 Starting generate_ai_landing_page...
      ✅ Completed generate_ai_landing_page
      ✅ Landing page created!
      
      Your professional landing page is ready. It features:
      • Compelling hero section with your value proposition
      • Executive-focused design
      • Clear "Schedule Consultation" CTA
      
      [Preview] [Edit]
```

**Build an Email Campaign:**
```
You: Send a campaign to my top customers about the holiday sale

AMOS: 🤔 Analyzing your request...
      🎯 Found perfect template: email_campaign_v2
      
      I can help with that! A few questions:
      • What's the subject line?
      • When should it send?
      • Any special discount or offer to highlight?

You: Subject: "Exclusive Holiday Sale - 30% Off for VIPs"
     Send it tomorrow at 10am
     Highlight 30% off everything

AMOS: 🔧 Creating email template...
      🔧 Setting up campaign...
      ✅ Campaign created and scheduled!
      
      Campaign: "Holiday Sale 2024"
      • Recipients: 156 top customers
      • Scheduled: Tomorrow at 10:00 AM
      • Template: VIP Holiday Sale
      
      Ready to send! 🎉
```

---

## 🔧 Creating Custom Workflows

### Workflow Template Structure (V2)

```yaml
template_version: 2
name: "Your Workflow Name"
slug: "your_workflow_slug_v2"
description: "What this workflow does"
category: "campaign_management"

keywords:
  - "trigger phrase 1"
  - "trigger phrase 2"

phases:
  # Phase 1: Gather information
  - id: "gather_context"
    type: "gather_context"
    name: "Collect Requirements"
    goal: "Gather all needed information"
    
    required_fields:
      - key: "field_name"
        prompt: "What's the question?"
        required: true
        validation: "text|email|url|number"
    
    context_sources:
      - "direct_conversation"
      - "conversation_history"
      - "entity_profile"
    
    ai_instructions: |
      Ask conversationally for the information.
      Be friendly and explain why you need each piece.

  # Phase 2: Execute the task
  - id: "execute_goal"
    type: "execute_goal"
    name: "Do The Work"
    goal: "Accomplish the main objective"
    
    # Option A: Structured (reliable, explicit)
    data_mapping:
      tool: "tool_name"
      args:
        field1: "{{gathered_field}}"
        field2: "{{another_field}}"
    
    execution_strategy:
      approach: "structured"  # or "adaptive"
      allowed_tools:
        - tool_name
    
    # Option B: Adaptive (flexible, AI-planned)
    # execution_strategy:
    #   approach: "adaptive"
    #   allowed_tools:
    #     - tool1
    #     - tool2
    
    ai_instructions: |
      Use the tools to accomplish the goal.

  # Phase 3: Validate
  - id: "validation"
    type: "validate_result"
    name: "Quality Check"
    goal: "Ensure success"
    
    validation_rules:
      - rule: "ai_check"
        check: "The output meets requirements"
    
    success_message: |
      ✅ Task complete! Here's what was done...
```

### Adding a New Template

1. Create file: `app/workflow_templates/your_template_v2.yml`
2. Follow the structure above
3. Test: AMOS will auto-discover it
4. Use: Trigger with keywords or description match

---

## 🛠️ Development

### Project Structure

```
app/
├── controllers/
│   └── scout_controller.rb          # Main chat interface
├── services/
│   ├── planner_agent_service.rb     # Workflow planning
│   ├── workflow_engine.rb           # Workflow orchestration
│   ├── bedrock_service.rb           # AWS Claude integration
│   ├── agents/
│   │   ├── gather_context_executor.rb
│   │   ├── goal_executor.rb
│   │   └── validation_executor.rb
│   └── tools/
│       ├── generate_landing_page_tool.rb
│       ├── create_object_tool.rb
│       ├── update_object_tool.rb
│       └── [18 more tools...]
├── models/
│   ├── campaign.rb
│   ├── contact.rb
│   ├── landing_page.rb
│   ├── workflow_execution.rb
│   └── workflow_context.rb
├── workflow_templates/
│   ├── landing_page_creation_v2.yml
│   ├── email_campaign_v2.yml
│   └── add_group_to_campaign_v2.yml
└── views/
    └── layouts/
        └── application.html.erb     # Main workspace UI

config/
└── routes.rb                        # API and chat endpoints

db/
├── schema.rb                        # Database structure
└── migrate/                         # Migrations
```

### Key Technologies

**Backend:**
- Ruby on Rails 8.0
- PostgreSQL (primary database)
- AWS Bedrock (Claude Sonnet 4.5)
- ActionCable (real-time streaming)
- SolidQueue (background jobs)

**Frontend:**
- Bootstrap 5 (responsive UI)
- Stimulus.js (JavaScript framework)
- Turbo (SPA-like experience)
- Server-Sent Events (SSE streaming)

### Running Tests

```bash
# Run full test suite
rails test

# Run specific test
rails test test/models/campaign_test.rb

# Test AI agent system
rails test:agents
```

### Development Workflow

```bash
# Start development server with hot reload
bin/dev

# Run migrations
rails db:migrate

# Create a new tool
rails generate service tools/your_tool_tool

# Load Rails console for debugging
rails console

# View logs
tail -f log/development.log
```

---

## 📚 Workflow Template Guide

### Template Categories

**Content Generation:**
- `landing_page_creation_v2` - Create professional landing pages
- Future: Blog posts, social media content, ads

**Campaign Management:**
- `email_campaign_v2` - Create and manage email campaigns
- `add_group_to_campaign_v2` - Associate contact groups

**Analytics:**
- Future: Performance dashboards, insights generation

**Data Management:**
- Future: Contact import, data cleanup, bulk operations

### Execution Strategies

**Structured (Recommended):**
```yaml
execution_strategy:
  approach: "structured"
  
data_mapping:
  tool: "create_object"
  args:
    object_type: "campaigns"
    data:
      name: "{{campaign_name}}"
      status: "draft"
```
- **Pros**: Reliable, explicit, predictable
- **Cons**: Less flexible
- **Use When**: Clear data mapping possible

**Adaptive (Flexible):**
```yaml
execution_strategy:
  approach: "adaptive"
  allowed_tools:
    - create_object
    - update_object
    - get_data
```
- **Pros**: Flexible, handles edge cases
- **Cons**: AI-dependent, may vary
- **Use When**: Complex logic or conditional steps

### Context Sources

Templates can gather data from:

1. **`direct_conversation`** - Ask the user directly
2. **`conversation_history`** - Extract from chat history
3. **`entity_profile`** - Use business/user info
4. **`workflow_context`** - Data from previous phases
5. **`uploaded_files`** - Analyze PDFs, images, docs

---

## 🔌 Integration System - Connect Everything

### The Power of Unified Data Access

AMOS's **integration system** is a game-changer. Connect external services and let AMOS orchestrate workflows **across multiple platforms** seamlessly.

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  "Thank my last Stripe customer who signed up yesterday"    │
└─────────────────────────────────────────────────────────────┘
                              ↓
        ┌─────────────────────────────────────┐
        │   AMOS Intelligently Orchestrates    │
        └─────────────────────────────────────┘
                   ↓                    ↓
        ┌──────────────────┐  ┌──────────────────┐
        │  Stripe API      │  │  Mailgun API     │
        │  Get Customers   │  │  Send Email      │
        └──────────────────┘  └──────────────────┘
                   ↓                    ↓
        ┌────────────────────────────────────────┐
        │  ✅ Email sent to Sarah J. via Mailgun │
        │     Subject: "Welcome to [Business]!"  │
        │     Used Stripe data for personalization│
        └────────────────────────────────────────┘
```

### Supported Integrations

**Payment Processors:**
- 💳 **Stripe** - Accept payments, manage subscriptions, customer data
- 💰 **PayPal** (Coming soon)

**CRM & Sales:**
- 🎯 **HubSpot** - Contacts, deals, pipeline management
- 📊 **Salesforce** (Coming soon)
- 🔧 **Custom CRMs** - Add any REST API

**Email & Communication:**
- ✉️ **Mailgun** - Transactional emails, bulk sending, tracking
- 📧 **SendGrid** (Coming soon)
- 💬 **Slack** (Coming soon)

**Productivity:**
- 📁 **Google Drive** - File management, document sharing
- 📅 **Google Calendar** (Coming soon)
- 📝 **Notion** (Coming soon)

**Analytics:**
- 📊 **Google Analytics** - Traffic, conversions, behavior
- 📈 **Custom Analytics APIs** - Add your own

**Custom Integrations:**
- 🛠️ **Any REST API** - User-configurable, no coding required!

### Real-World Use Cases

#### 1️⃣ **Cross-Platform Customer Engagement**

```
You: "Send a thank you email to customers who bought something today"

AMOS: 🤔 Analyzing request...
      🔧 Connecting to Stripe...
      📊 Found 3 new customers today
      
      Customers who purchased:
      • Sarah Johnson - $149.00 - Premium Plan
      • Mike Chen - $49.00 - Starter Plan  
      • Lisa Rodriguez - $299.00 - Enterprise Plan
      
      🔧 Creating personalized emails...
      ✅ 3 thank you emails queued via Mailgun
      
      Each email includes:
      • Personal greeting
      • Order details
      • Next steps for their plan
      • Support contact info
      
      Emails will send in the next 5 minutes! 📧
```

#### 2️⃣ **Data Sync Across Platforms**

```
You: "Add all my Stripe customers to HubSpot"

AMOS: 🔧 Fetching Stripe customers...
      📊 Found 1,247 customers
      
      🔧 Checking HubSpot for existing contacts...
      📊 834 already exist, 413 new
      
      🔧 Creating 413 new contacts in HubSpot...
      ✅ Done! HubSpot now has all 1,247 customers
      
      Summary:
      • 413 new contacts created
      • 834 existing contacts verified
      • All with complete payment history
      • Synced subscription status
      
      Set up auto-sync? I can keep them in sync daily! 🔄
```

#### 3️⃣ **Intelligent Follow-ups**

```
You: "Send a reminder to HubSpot leads who haven't responded in 7 days"

AMOS: 🔧 Analyzing HubSpot deals...
      📊 Found 23 leads with no activity in 7+ days
      
      Leads to follow up:
      • Enterprise prospects: 8
      • Mid-market: 12
      • Small business: 3
      
      🔧 Generating personalized reminders...
      ✅ Created 23 custom emails based on:
         • Their original inquiry
         • Industry
         • Deal size
         • Last interaction
      
      Review first email? Or send all? 📨
```

#### 4️⃣ **Automated Reporting**

```
You: "Create a weekly sales report and email it to my team"

AMOS: 🔧 Pulling data from Stripe, HubSpot, and our campaigns...
      📊 Generating comprehensive report...
      
      ✅ Weekly Sales Report Created!
      
      📈 This Week's Highlights:
      • Revenue: $12,450 (+18% vs last week)
      • New Customers: 15
      • Email Campaign Performance: 32% open rate
      • HubSpot Deals Closed: 4 ($8,200 value)
      
      📧 Report emailed to:
      • team@business.com
      • manager@business.com
      
      Should I schedule this to run every Monday at 9 AM? 🔄
```

#### 5️⃣ **Smart Data Import**

```
You: "Import my Stripe customers as contacts and create segments"

AMOS: 🔧 Connecting to Stripe...
      📊 Analyzing 1,247 customers...
      
      🔧 Creating contact segments based on:
      • Subscription tier (Free, Pro, Enterprise)
      • Lifetime value
      • Account age
      • Payment history
      
      ✅ Import Complete!
      
      Created 5 smart segments:
      • VIP Customers (>$1000 LTV): 87 contacts
      • Recent Upgrades (last 30 days): 34 contacts
      • At Risk (payment failed): 12 contacts
      • Trial Users: 156 contacts
      • Inactive (>90 days): 45 contacts
      
      Ready to create targeted campaigns! 🎯
```

### How Integration Works

#### Step 1: Connect an Integration

```
You: "Connect my Stripe account"

AMOS: I'll help you connect Stripe! 
      
      To get started:
      1. Go to Stripe Dashboard > Developers > API Keys
      2. Copy your Secret Key (starts with sk_live_ or sk_test_)
      3. Paste it here
      
      [Secure input field appears]

You: [Pastes API key]

AMOS: 🔧 Testing connection...
      ✅ Connected successfully!
      
      Your Stripe account is now connected.
      I can now:
      • View customer data
      • Check subscription status
      • Process payments
      • Generate revenue reports
      
      What would you like to do first? 🚀
```

#### Step 2: Use Across Workflows

Once connected, integrations are **automatically available** in all workflows:

```ruby
# AMOS can now chain operations across platforms
1. Get Stripe customers → Filter by criteria
2. Check HubSpot for deal status → Update in CRM
3. Send personalized email → Via Mailgun
4. Create Google Doc report → Share with team
```

### Integration Features

**🔐 Secure:**
- Encrypted credential storage
- OAuth 2.0 support
- API key management
- Scope-based permissions

**📊 Smart:**
- Automatic pagination handling
- Rate limit management
- Request validation
- Response transformation

**🔄 Reliable:**
- Automatic retries
- Error handling
- Transaction logging
- Audit trail

**🎯 Flexible:**
- Data-driven (no code changes)
- User-configurable
- Custom API support
- Exportable/shareable

### Integration Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   AMOS AI Engine                          │
│  (Plans workflows, selects operations, chains actions)    │
└──────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────┐
│              Integration Tool Layer                       │
│  • list_connections - Discover connected services         │
│  • list_operations - See available API calls              │
│  • invoke_operation - Execute API operations              │
└──────────────────────────────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────┐
│           IntegrationApiService                           │
│  • Handles authentication (API key, OAuth, Basic)         │
│  • Manages rate limits & quotas                           │
│  • Validates requests/responses                           │
│  • Logs all operations                                    │
└──────────────────────────────────────────────────────────┘
                           ↓
┌───────────┬─────────────┬──────────────┬────────────────┐
│  Stripe   │  HubSpot    │   Mailgun    │  Custom APIs   │
│  API      │  API        │   API        │  (User-added)  │
└───────────┴─────────────┴──────────────┴────────────────┘
```

### Available Integration Tools

**For Users:**
- `list_connections` - See your connected services
- `list_operations` - View available API operations  
- `invoke_operation` - Execute API calls through AMOS

**For AMOS (AI):**
- Discovers available integrations automatically
- Plans multi-step workflows across platforms
- Handles authentication and API details
- Transforms data between systems
- Chains operations intelligently (Stripe → HubSpot → Mailgun)

### Integration Data Models

**Integration** - The service definition (Stripe, HubSpot, etc.)
```ruby
- name, slug, category
- auth_type, api_base_url
- operations (what it can do)
```

**Connection** - User's specific account
```ruby
- belongs_to :integration
- belongs_to :entity
- credentials (encrypted)
- status, rate_limits
```

**IntegrationOperation** - Specific API endpoint
```ruby
- operation_id (e.g., "stripe.list_customers.v1")
- http_method, path_template
- request_schema, response_schema
- pagination_strategy
```

**IntegrationLog** - Audit trail
```ruby
- Every API call logged
- Request/response captured
- Performance metrics
- Error tracking
```

### Adding Custom Integrations

Users can add **any REST API** without code:

1. **Go to Settings > Integrations > Add Custom**
2. **Fill in details:**
   - API Base URL
   - Authentication type
   - Headers/credentials
3. **Define operations:**
   - Endpoint paths
   - HTTP methods
   - Request/response schemas
4. **Test & Activate**

**Example: Internal Tool Integration**
```
Name: Company Inventory System
Base URL: https://inventory.mycompany.com/api
Auth: API Key
Operations:
  - Get Stock Levels
  - Create Purchase Order
  - Update Quantities
```

Now AMOS can say:
> "Your top SKU is low on stock. Should I create a purchase order?"

### Cross-Platform Automation Examples

**Sales Pipeline:**
```
Stripe payment received 
  → Update HubSpot deal status
  → Send welcome email (Mailgun)
  → Create Google Drive folder for client
  → Notify team in Slack
```

**Marketing Automation:**
```
Campaign sent (Mailgun)
  → Track opens/clicks
  → Update contact segments
  → Sync engagement to HubSpot
  → Trigger follow-up workflows
```

**Customer Success:**
```
Stripe subscription canceled
  → Flag in HubSpot
  → Send save offer email
  → Create support ticket
  → Notify retention team
```

---

## 🎙️ Voice Interface (Coming V2.1)

AMOS will support **voice commands** for hands-free, natural interaction:

### Voice Capabilities

**Input Methods:**
- 🎤 **Web Voice Input** - Click to talk in browser
- 📱 **Mobile Voice** - Native speech recognition
- 📞 **Phone Integration** - Call AMOS directly
- 🎧 **Always-On Mode** - Wake word activation

**Output Methods:**
- 🔊 **Natural Speech** - AI-generated voice responses
- 📻 **Streaming Audio** - Real-time audio feedback
- 🔔 **Audio Notifications** - Important updates via sound

### Voice Use Cases

**Hands-Free Business Management:**
```
🎤 "Hey AMOS, how many customers signed up today?"
🔊 "You have 7 new customers today. 4 from Stripe, 3 from your landing page.
     Total revenue: $423. Would you like me to send them welcome emails?"

🎤 "Yes, send welcome emails"
🔊 "Creating personalized emails now... Done! 7 emails sent via Mailgun.
     I've also updated their records in HubSpot."
```

**On-the-Go Operations:**
```
🎤 "AMOS, how's my spring campaign performing?"
🔊 "Your spring campaign has a 34% open rate and 12% click rate.
     That's 8% above your average! 127 people clicked through.
     Should I send a follow-up to the unopened contacts?"

🎤 "Not yet, check again tomorrow"
🔊 "Got it. I'll remind you tomorrow at 9 AM to review the campaign."
```

**Quick Status Checks:**
```
🎤 "Any new leads in HubSpot?"
🔊 "Yes, 3 new leads since this morning. Two enterprise prospects 
     and one mid-market. Want me to create follow-up tasks?"
```

**Driving-Safe Workflows:**
```
🎤 "Schedule a campaign for next Monday"  
🔊 "I'll help you create that. Which contact group should receive it?"

🎤 "My VIP customers"
🔊 "Perfect. What's the subject line?"

🎤 "Holiday Special - 30% Off"
🔊 "Great! Campaign scheduled for Monday at 10 AM to 87 VIP customers.
     I'll send you a preview link via email for final approval."
```

### Technical Approach

**Voice Input:**
- Web Speech API for browser
- Native speech recognition on mobile
- Twilio integration for phone calls
- WebRTC for real-time audio

**Voice Output:**
- AI-generated natural speech (ElevenLabs or AWS Polly)
- Conversational tone matching
- Multi-language support
- Adjustable speed/voice

**Smart Features:**
- Context-aware (knows what you're working on)
- Ambient noise filtering
- Multi-turn conversations
- Voice authentication (optional)

Imagine managing your entire business **while driving, cooking, or in a meeting**! 🚗🎧

---

## 🔌 API & Integrations (Developer Guide)

### Chat API

**Endpoint:** `POST /scout/chat_stream`

```javascript
// JavaScript example
const eventSource = new EventSource('/scout/chat_stream');

eventSource.onmessage = (event) => {
  const data = JSON.parse(event.data);
  
  switch(data.type) {
    case 'content':
      // Append message content
      appendMessage(data.content);
      break;
    case 'transient':
      // Show progress indicator
      showProgress(data.message);
      break;
    case 'load_canvas':
      // Load UI component
      loadCanvas(data.canvas, data.data);
      break;
  }
};

// Send message
fetch('/scout/chat_stream', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ message: 'Create a landing page' })
});
```

### Tool Development

Create new tools by extending `BaseTool`:

```ruby
module Tools
  class YourCustomTool < BaseTool
    def self.definition
      {
        name: 'your_custom_tool',
        description: 'What this tool does',
        category: 'data',
        parameters: {
          type: 'object',
          properties: {
            param1: {
              type: 'string',
              description: 'Parameter description'
            }
          },
          required: ['param1']
        }
      }
    end
    
    def execute(args)
      # Your tool logic here
      param1 = get_arg(args, :param1)
      
      # Return success or error
      success_response(
        message: "Tool executed successfully!",
        data: { result: 'value' }
      )
    rescue => e
      error_response("Error: #{e.message}")
    end
  end
end
```

Tools are **auto-discovered** and immediately available to AMOS.

---

## 🎨 UI Components

### Chat Interface Features

- **Streaming Responses**: Real-time message display
- **Transient Messages**: Temporary progress indicators (fade after completion)
- **Tool Indicators**: Show which tools are running
- **Canvas Loading**: Dynamic UI components (landing page editor, campaign dashboard)
- **Markdown Support**: Rich formatting in responses
- **Code Blocks**: Syntax-highlighted examples

### Canvas System

AMOS can load specialized UI components:

- `landing_page_viewer` - Preview landing pages
- `landing_page_editor` - Edit landing page HTML/settings
- `campaign_dashboard` - Campaign performance metrics
- `task_progress` - Workflow approval and progress
- `contact_manager` - Contact list management

---

## 📊 Data Models

### Core Entities

**Campaign**
```ruby
# A marketing campaign
belongs_to :email_template
has_many :campaign_groups
has_many :contact_groups, through: :campaign_groups
has_many :email_deliveries

# Key fields: name, description, status, scheduled_at
```

**Contact & ContactGroup**
```ruby
# One-to-many relationship via join table
ContactGroup
  has_and_belongs_to_many :contacts

Campaign
  has_many :contact_groups, through: :campaign_groups
```

**LandingPage**
```ruby
# AI-generated landing pages
belongs_to :entity
belongs_to :user

# Key fields: title, slug, html_content, status, metadata
```

**WorkflowExecution & WorkflowContext**
```ruby
# Tracks workflow runs and persistent data
WorkflowExecution
  has_many :workflow_contexts
  has_many :workflow_step_executions

WorkflowContext
  # key, value, data_type, metadata
  # Stores data between workflow phases
```

---

## 🔐 Security & Best Practices

### AI Safety
- Tool allowlists per agent role
- Input validation on all tools
- Sanitization of AI-generated HTML
- Rate limiting on AI API calls

### Data Privacy
- Entity-scoped data access
- User authentication (Devise)
- GDPR-compliant contact management
- Encrypted credentials (Rails credentials)

### Performance
- Background job processing (SolidQueue)
- Database indexing on common queries
- Caching for frequently accessed data
- Streaming responses for better UX

---

## 📈 Roadmap

### Current (V2.0) ✅
**Core Platform:**
- ✅ Phase-based workflow system
- ✅ Intelligent context gathering
- ✅ Structured & adaptive execution
- ✅ 3 production templates
- ✅ 20+ AI tools
- ✅ Real-time progress streaming

**Integrations:**
- ✅ Stripe integration (payments, customers, subscriptions)
- ✅ HubSpot integration (CRM, contacts, deals)
- ✅ Custom API integration framework
- ✅ Cross-platform workflow orchestration
- ✅ Secure credential management
- ✅ Operation discovery & execution

### Coming Soon (V2.1) 🚀
**Integration Expansion:**
- 🔄 Enhanced integration builder UI
- 🔄 Integration marketplace (share/discover)
- 🔄 More pre-built integrations (Mailgun, SendGrid, Slack)
- 🔄 Webhook automation (trigger workflows from external events)
- 🔄 Scheduled sync workflows

**Voice Interface (HIGH PRIORITY):**
- 🎙️ Voice command input
- 🔊 Natural language audio responses
- 📞 Phone number integration
- 🎧 Hands-free operation mode

**Platform Enhancements:**
- 🔄 Multi-entity collaboration
- 🔄 Advanced analytics dashboards
- 🔄 Template marketplace
- 🔄 Mobile-optimized UI

### Future (V3.0) 🎯
**Advanced AI:**
- 🎯 Multi-agent collaboration (parallel task execution)
- 🎯 Proactive recommendations ("Your campaign performance is down, should I...")
- 🎯 Predictive workflows (anticipate needs)
- 🎯 Learning from patterns (improve over time)

**Enterprise Features:**
- 🎯 Team collaboration features
- 🎯 Role-based access control
- 🎯 Advanced audit logging
- 🎯 White-label options

**Integration Ecosystem:**
- 🎯 100+ pre-built integrations
- 🎯 Visual workflow builder
- 🎯 Integration analytics
- 🎯 Bidirectional sync automation

---

## 🤝 Contributing

AMOS is designed to be extensible. Contribute by:

1. **Creating Templates** - Add YAML files to `app/workflow_templates/`
2. **Building Tools** - Extend functionality in `app/services/tools/`
3. **Enhancing UI** - Improve chat interface and canvas components
4. **Documentation** - Help others understand the system

---

## 📝 Documentation

**Key Documentation Files:**
- `WORKFLOW_V2_EXECUTIVE_SUMMARY.md` - V2 workflow architecture overview
- `V2_PURE_IMPLEMENTATION.md` - Implementation details
- `WORKFLOW_V2_IMPLEMENTATION_COMPLETE.md` - Migration guide
- `docs/AGENT_TESTING_GUIDE.md` - Testing agent systems
- `docs/INTEGRATION_EXAMPLE.md` - Integration patterns

---

## 🐛 Troubleshooting

### Common Issues

**AMOS not responding:**
- Check AWS Bedrock credentials
- Verify ActionCable connection
- Check logs: `tail -f log/development.log`

**Workflow fails:**
- Check workflow execution logs in database
- Review `WorkflowExecution` and `WorkflowContext` tables
- Enable debug logging for phase executors

**Tool errors:**
- Verify tool is registered in `ToolCatalog`
- Check tool parameter format
- Review tool execution logs

### Debug Mode

```ruby
# Enable detailed logging
Rails.logger.level = :debug

# Check workflow context
WorkflowContext.where(workflow_execution_id: 123)

# Review tool catalog
Tools::ToolCatalog.instance.all_tools.keys
```

---

## 📞 Support

- **Issues**: [GitHub Issues](repository-issues-url)
- **Discussions**: [GitHub Discussions](repository-discussions-url)
- **Email**: support@amoslabs.ai
- **Documentation**: [Full Docs](docs-url)

---

## 📄 License

[Your License Here]

---

## 🙏 Acknowledgments

Built with:
- **AWS Bedrock** - Claude AI foundation
- **Ruby on Rails** - Robust web framework
- **Bootstrap** - Beautiful responsive UI
- **The Open Source Community** - Countless amazing libraries

---

**AMOS** - Making business automation as simple as having a conversation. 🚀

*Version 2.0 - October 2025*
