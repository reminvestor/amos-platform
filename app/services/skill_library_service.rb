# frozen_string_literal: true

# SkillLibraryService - Dynamic skill/expertise injection for AMOS
#
# This extends the GuidanceLibrary concept to support:
# 1. User-uploaded SKILL.md files (Claude format)
# 2. Integration-specific skills (Stripe, QuickBooks, etc.)
# 3. Semantic discovery (find relevant skills based on message)
#
# Philosophy:
# - Skills are NOT agents - they're expertise that AMOS uses directly
# - Skills are like "how-to guides" that get injected into context
# - Tools are what you DO, Skills are HOW you do it
#
# Usage:
#   skill = SkillLibraryService.discover_skill(
#     message: "Get the last 10 charges from Stripe",
#     entity: entity,
#     integrations: ["stripe"]
#   )
#   # Returns skill content to inject into AMOS's prompt
#
class SkillLibraryService
  # ═══════════════════════════════════════════════════════════════
  # SKILL DISCOVERY
  # ═══════════════════════════════════════════════════════════════

  # Discover relevant skills for a message
  # Returns: { skill_block: String, source: String, skill_names: Array }
  def self.discover_skills(message:, entity: nil, integrations: [], canvas_context: nil, limit: 3)
    skills_found = []
    
    # Priority 1: Integration-specific skills (if integrations mentioned)
    if integrations.any?
      integrations.each do |integration_name|
        skill = get_integration_skill(integration_name)
        skills_found << skill if skill
      end
    end
    
    # Priority 2: Canvas-based skills (if on a specific canvas)
    if canvas_context.present?
      canvas_skill = get_canvas_skill(canvas_context)
      skills_found << canvas_skill if canvas_skill
    end
    
    # Priority 3: Keyword-based skills from message
    keyword_skills = detect_skills_from_message(message)
    skills_found.concat(keyword_skills)
    
    # Priority 4: Entity's custom uploaded skills (semantic search)
    if entity.present?
      custom_skills = search_custom_skills(message: message, entity: entity, limit: limit)
      skills_found.concat(custom_skills)
    end
    
    # Deduplicate and limit
    skills_found = skills_found.uniq { |s| s[:name] }.first(limit)
    
    return nil if skills_found.empty?
    
    # Build combined skill block
    skill_block = build_skill_block(skills_found)
    skill_names = skills_found.map { |s| s[:name] }
    
    Rails.logger.info "📚 [SkillLibrary] Injecting #{skills_found.size} skills: #{skill_names.join(', ')}"
    
    {
      skill_block: skill_block,
      skill_names: skill_names,
      skills: skills_found,
      source: skills_found.map { |s| s[:source] }.uniq.join(', ')
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # INTEGRATION SKILLS
  # Pre-defined skills for common integrations
  # ═══════════════════════════════════════════════════════════════

  INTEGRATION_SKILLS = {
    'stripe' => {
      name: 'Stripe API Expert',
      source: 'built-in',
      content: <<~SKILL.strip
        ## Stripe Integration Skill
        
        ### Key Patterns
        - All amounts are in CENTS (divide by 100 for display)
        - Use `limit` parameter (max 100) for list operations
        - Use `starting_after` for pagination (cursor-based)
        - Date filters use `created[gte]` and `created[lte]` (Unix timestamps)
        
        ### Common Operations
        - `list_charges` - Get payment history
        - `list_customers` - Get customer list
        - `list_subscriptions` - Active subscriptions
        - `list_invoices` - Invoice history
        - `retrieve_balance` - Current balance
        
        ### DO NOT USE these parameters (they don't exist):
        ❌ `order`, `sort`, `sort_by`, `direction` - Stripe doesn't support sorting
        ❌ `status` on charges - Use `paid` boolean filter instead
        
        ### Example: Get recent charges
        ```
        execute_integration_action(
          integration: "stripe",
          action: "list_charges",
          inputs: { limit: 10 }
        )
        ```
        
        ### Currency Display
        Stripe returns amounts in cents. When displaying:
        - $699 charge → shows as 69900 in API → display as $699.00
      SKILL
    },

    'quickbooks' => {
      name: 'QuickBooks API Expert',
      source: 'built-in',
      content: <<~SKILL.strip
        ## QuickBooks Integration Skill
        
        ### Query Language
        QuickBooks uses SQL-like queries, NOT REST parameters:
        
        ```
        execute_integration_action(
          integration: "quickbooks",
          action: "query",
          inputs: { query: "SELECT * FROM Invoice WHERE Balance > '0'" }
        )
        ```
        
        ### Query Examples
        - Open invoices: `SELECT * FROM Invoice WHERE Balance > '0'`
        - Recent customers: `SELECT * FROM Customer ORDERBY MetaData.CreateTime DESC MAXRESULTS 10`
        - Specific customer: `SELECT * FROM Customer WHERE DisplayName LIKE '%Smith%'`
        
        ### Common Entities
        - `Invoice` - Customer invoices
        - `Customer` - Customer records
        - `Payment` - Payment records
        - `Bill` - Vendor bills
        - `Vendor` - Vendor records
        
        ### DO NOT USE:
        ❌ `Status` field on invoices - Use `Balance > '0'` for unpaid
        ❌ REST-style filters - Use SQL queries instead
        
        ### Date Filtering
        Use: `WHERE TxnDate > '2024-01-01'`
      SKILL
    },

    'hubspot' => {
      name: 'HubSpot API Expert',
      source: 'built-in',
      content: <<~SKILL.strip
        ## HubSpot Integration Skill
        
        ### Key Concepts
        - Objects: contacts, companies, deals, tickets
        - Properties define custom fields
        - Associations link objects together
        
        ### Common Operations
        - `list_contacts` - Get contact list
        - `create_contact` - Create new contact
        - `list_deals` - Get deal pipeline
        - `create_deal` - Create new deal
        
        ### Required Fields
        - Contacts: `email` (required), `firstname`, `lastname`
        - Deals: `dealname` (required), `amount`, `dealstage`
        
        ### Pagination
        Use `after` cursor for pagination, not `offset`.
      SKILL
    },

    'mailgun' => {
      name: 'Mailgun API Expert',
      source: 'built-in',
      content: <<~SKILL.strip
        ## Mailgun Integration Skill
        
        ### Sending Email
        ```
        execute_integration_action(
          integration: "mailgun",
          action: "send_email",
          inputs: {
            from: "sender@domain.com",
            to: "recipient@example.com",
            subject: "Subject line",
            html: "<p>HTML content</p>"
          }
        )
        ```
        
        ### Required: Verified Domain
        The `from` address must use a verified domain.
        
        ### Tracking
        - Opens and clicks tracked automatically
        - Use `o:tracking` to disable
      SKILL
    },

    'trello' => {
      name: 'Trello API Expert',
      source: 'built-in',
      content: <<~SKILL.strip
        ## Trello Integration Skill

        ### Authentication
        - Uses API Key + Token as query parameters: `?key={apiKey}&token={token}`
        - Generate key at https://trello.com/power-ups/admin (API Key tab)
        - Token is user-specific and grants access to that user's boards

        ### Rate Limits
        - 300 requests per 10 seconds per API key
        - 100 requests per 10 seconds per token
        - Exceeding returns HTTP 429

        ### Available Operations
        - `List My Boards` — GET /1/members/me/boards
        - `Get Board` — GET /1/boards/{id} (includes name, desc, url)
        - `Get Board Members` — GET /1/boards/{id}/members
        - `Get Lists On Board` — GET /1/boards/{id}/lists
        - `Get Cards On List` — GET /1/lists/{id}/cards
        - `Get Card` — GET /1/cards/{id}
        - `Get Checklists On Card` — GET /1/cards/{id}/checklists
        - `Create Board` — POST /1/boards (name required)
        - `Create Card` — POST /1/cards (name, idList required)
        - `Create List` — POST /1/lists (name, idBoard required)
        - `Create Checklist` — POST /1/checklists (idCard required)
        - `Create Checklist Item` — POST /1/checklists/{id}/checkItems
        - `Update Card` — PUT /1/cards/{id} (name, desc, due, idList, closed)
        - `Update Board` — PUT /1/boards/{id}
        - `Update List` — PUT /1/lists/{id} (name, closed, pos)
        - `Delete Card` — DELETE /1/cards/{id}
        - `Delete Board` — DELETE /1/boards/{id}

        ### Common Patterns
        - To move a card: Update Card with new `idList`
        - To archive a card: Update Card with `closed: true`
        - To find a specific board's cards: List My Boards → Get Lists On Board → Get Cards On List
        - Card fields: name, desc, due, dueComplete, idList, idBoard, labels, closed, pos, url

        ### Example: Create a card
        ```
        execute_integration_action(
          integration: "trello",
          action: "Create Card",
          inputs: { name: "New task", idList: "LIST_ID", desc: "Description" }
        )
        ```
      SKILL
    },

    'godaddy' => {
      name: 'GoDaddy API Expert',
      source: 'built-in',
      content: <<~SKILL.strip
        ## GoDaddy Integration Skill

        ### Authentication
        - Uses `sso-key {api_key}:{api_secret}` in Authorization header
        - Production: https://api.godaddy.com
        - Keys generated at https://developer.godaddy.com/keys
        - IMPORTANT: DNS API requires 10+ domains on the account (GoDaddy restriction since April 2024)

        ### Available Operations
        - `List Domains` — GET /v1/domains (returns all domains on account)
        - `Verify Domain Ownership` — GET /v1/domains/{domain} (domain details, status, expiry)
        - `Get DNS Records` — GET /v1/domains/{domain}/records (all DNS records)
        - `Add DNS Record` — PATCH /v1/domains/{domain}/records (append records)
        - `Replace DNS Records` — PUT /v1/domains/{domain}/records/{type} (replace all records of a type)
        - `Delete DNS Record` — DELETE /v1/domains/{domain}/records/{type}/{name}

        ### DNS Record Format
        Records are JSON objects: `{ type: "A", name: "@", data: "1.2.3.4", ttl: 600 }`
        - `type`: A, AAAA, CNAME, MX, TXT, NS, SRV, SOA
        - `name`: "@" for root, or subdomain name
        - `data`: record value (IP address, domain, text)
        - `ttl`: time-to-live in seconds (min 600)

        ### Common Tasks
        - Point domain to IP: Add/Replace A record with `name: "@"`, `data: "IP_ADDRESS"`
        - Add subdomain: Add CNAME record with `name: "subdomain"`, `data: "target.domain.com"`
        - Verify domain (email): Add TXT record for SPF/DKIM/DMARC
        - Add MX records: `{ type: "MX", name: "@", data: "mail.provider.com", priority: 10 }`

        ### Example: Add a CNAME record
        ```
        execute_integration_action(
          integration: "godaddy",
          action: "Add DNS Record",
          inputs: { domain: "example.com", records: [{ type: "CNAME", name: "www", data: "example.com", ttl: 600 }] }
        )
        ```

        ### DO NOT:
        ❌ Use `Replace DNS Records` unless you intend to overwrite ALL records of that type
        ❌ Forget the domain path parameter (it's the actual domain name, e.g., "example.com")
      SKILL
    },

    'gmail' => {
      name: 'Gmail API Expert',
      source: 'built-in',
      content: <<~SKILL.strip
        ## Gmail Integration Skill

        ### Authentication
        - OAuth 2.0 with Google scopes
        - Base URL: https://gmail.googleapis.com/gmail/v1
        - Use `me` as userId for the authenticated user

        ### Available Operations
        - `List Messages` — GET /users/me/messages (returns id + threadId only)
        - `Get Message` — GET /users/me/messages/{id} (full message with body)
        - `Send Email` — POST /users/me/messages/send (requires base64url-encoded RFC 2822 message)
        - `Test Connection` — GET /users/me/profile

        ### Key Patterns
        - **List Messages returns ONLY IDs** — you must call Get Message for each message to read content
        - Use `q` parameter for Gmail search syntax: `q: "from:user@example.com after:2024/01/01"`
        - `maxResults` defaults to 100, max 500
        - Pagination via `pageToken` (returned in response as `nextPageToken`)
        - Message format options: `full` (default), `metadata`, `minimal`, `raw`

        ### Gmail Search Syntax (q parameter)
        - `from:user@example.com` — from specific sender
        - `to:user@example.com` — to specific recipient
        - `subject:invoice` — subject contains word
        - `after:2024/01/01` — after date
        - `before:2024/12/31` — before date
        - `has:attachment` — has attachments
        - `is:unread` — unread messages
        - `label:important` — specific label

        ### Sending Email
        The message body must be a base64url-encoded RFC 2822 email string:
        ```
        From: sender@gmail.com
        To: recipient@example.com
        Subject: Hello

        Email body here
        ```

        ### DO NOT:
        ❌ Try to read message bodies from list results (only IDs returned)
        ❌ Send raw text as email body (must be base64url-encoded RFC 2822)
      SKILL
    },

    'slack' => {
      name: 'Slack API Expert',
      source: 'built-in',
      content: <<~SKILL.strip
        ## Slack Integration Skill

        ### Authentication
        Our Slack integration uses **Incoming Webhooks** (simplest approach):
        - Each webhook URL is tied to a specific channel
        - The webhook URL is the connection credential
        - No OAuth flow needed — just the webhook URL

        ### Available Operations
        - `Post Message (Webhook)` — POST to webhook URL with JSON payload
        - `Test Connection` — GET /api/auth.test (if using bot token)

        ### Posting Messages via Webhook
        ```
        execute_integration_action(
          integration: "slack",
          action: "Post Message (Webhook)",
          inputs: {
            text: "Hello from AMOS! 🤖"
          }
        )
        ```

        ### Rich Message Formatting (Block Kit)
        Slack supports rich formatting with blocks:
        ```json
        {
          "blocks": [
            { "type": "header", "text": { "type": "plain_text", "text": "New Lead!" } },
            { "type": "section", "text": { "type": "mrkdwn", "text": "*Name:* John Smith\\n*Email:* john@example.com" } }
          ]
        }
        ```

        ### Slack Markdown (mrkdwn)
        - `*bold*`, `_italic_`, `~strikethrough~`, `` `code` ``
        - `<https://example.com|Link text>` for links
        - `<@U12345>` to mention a user
        - `<!channel>` to notify everyone

        ### Webhook Limitations
        - One webhook = one channel
        - Cannot read messages (send only)
        - Cannot list channels or users
        - For advanced features, upgrade to Bot Token auth

        ### DO NOT:
        ❌ Try to read messages or list channels via webhook (send-only)
        ❌ Include the full webhook URL in tool inputs (it's stored in the connection)
      SKILL
    },

    'shopify' => {
      name: 'Shopify API Expert',
      source: 'built-in',
      content: <<~SKILL.strip
        ## Shopify Integration Skill

        ### Authentication
        - OAuth 2.0 with access token in `X-Shopify-Access-Token` header
        - Base URL pattern: `https://{store}.myshopify.com/admin/api/2024-10`
        - REST Admin API is legacy; Shopify recommends GraphQL for new apps

        ### Available Operations
        - `List Products` — GET /products.json (returns array of products)
        - `Test Connection` — GET /shop.json (returns shop details)

        ### Product Fields
        - `id`, `title`, `body_html`, `vendor`, `product_type`, `status`
        - `variants[]` — each has `price`, `sku`, `inventory_quantity`, `title`
        - `images[]` — product images with `src` URLs
        - `tags` — comma-separated string

        ### Pagination
        - Use `limit` parameter (max 250, default 50)
        - Cursor-based pagination via `Link` header
        - Response includes `page_info` parameter for next/prev

        ### Filtering Products
        - `status`: active, archived, draft
        - `product_type`: filter by type
        - `vendor`: filter by vendor
        - `collection_id`: products in a collection
        - `created_at_min` / `updated_at_min`: date filters (ISO 8601)

        ### Example: List active products
        ```
        execute_integration_action(
          integration: "shopify",
          action: "List Products",
          inputs: { limit: 50, status: "active" }
        )
        ```

        ### Important Notes
        - Prices are strings (e.g., "29.99"), NOT cents like Stripe
        - Inventory is per-variant, not per-product
        - Only last 60 days of orders by default (need `read_all_orders` scope)
      SKILL
    },

    'neon_crm' => {
      name: 'Neon CRM API Expert',
      source: 'built-in',
      content: <<~SKILL.strip
        ## Neon CRM Integration Skill

        ### Authentication
        - HTTP Basic Auth: username = Organization ID, password = API Key
        - Base URL: https://api.neoncrm.com/v2
        - Include header: `NEON-API-VERSION: 2.8`
        - Trial instances use: https://trial.z2systems.com/v2

        ### Available Operations
        - `List Accounts` — POST /accounts/search (search, NOT GET)
        - `Get Account` — GET /accounts/{id}
        - `Create Account` — POST /accounts
        - `Update Account` — PATCH /accounts/{id}
        - `List Donations` — POST /donations/search (search, NOT GET)
        - `Get Donation` — GET /donations/{id}
        - `List Events` — POST /events/search
        - `List Memberships` — GET /memberships
        - `List Custom Fields` — GET /customFields

        ### CRITICAL: Search Endpoints Use POST, Not GET
        Neon CRM uses POST requests with JSON body for searching:
        ```
        execute_integration_action(
          integration: "neon_crm",
          action: "List Accounts",
          inputs: {
            searchFields: [{ field: "Email", operator: "EQUAL", value: "john@example.com" }],
            outputFields: ["Account ID", "First Name", "Last Name", "Email 1"],
            pagination: { currentPage: 0, pageSize: 50 }
          }
        )
        ```

        ### Search Operators
        - `EQUAL`, `NOT_EQUAL`, `CONTAIN`, `NOT_CONTAIN`
        - `GREATER_THAN`, `LESS_THAN`, `GREATER_AND_EQUAL`, `LESS_AND_EQUAL`
        - `BLANK`, `NOT_BLANK`

        ### Common Search Fields
        - Accounts: "First Name", "Last Name", "Email", "Account Type", "Account ID"
        - Donations: "Amount", "Date", "Fund", "Campaign", "Account ID"
        - Events: "Event Name", "Event Start Date", "Event Status"

        ### Account Types
        - Individual, Organization, Household
        - Each has different required fields

        ### DO NOT:
        ❌ Use GET for list/search operations (they're POST with search body)
        ❌ Forget `outputFields` in search requests (controls which fields are returned)
        ❌ Use page numbers starting at 1 (pagination is 0-based)
      SKILL
    }
  }.freeze

  # ═══════════════════════════════════════════════════════════════
  # TASK-BASED SKILLS
  # Specialized skills for common task patterns
  # ═══════════════════════════════════════════════════════════════

  TASK_SKILLS = {
    'tdd' => {
      name: 'Test-Driven Development',
      keywords: %w[test tdd testing spec unit integration],
      source: 'built-in',
      content: <<~SKILL.strip
        ## Test-Driven Development Skill
        
        ### The TDD Cycle (MANDATORY)
        1. RED: Write failing test first
        2. GREEN: Write minimal code to pass
        3. REFACTOR: Clean up while tests pass
        
        ### Rails Testing Commands
        ```bash
        podman compose run --rm web rails test path/to/test.rb
        ```
        
        ### Key Rules
        - Test MUST fail before writing implementation
        - Write MINIMUM code to pass
        - Refactor only with green tests
      SKILL
    },

    'debugging' => {
      name: 'Systematic Debugging',
      keywords: %w[debug error bug fix broken failing crash exception],
      source: 'built-in',
      content: <<~SKILL.strip
        ## Debugging Skill
        
        ### Systematic Approach
        1. REPRODUCE: Confirm the exact error
        2. ISOLATE: Find the smallest failing case
        3. HYPOTHESIZE: Form theory about cause
        4. TEST: Verify hypothesis with targeted check
        5. FIX: Make minimal change
        6. VERIFY: Confirm fix doesn't break other things
        
        ### Common Rails Debugging
        - Check logs: `podman compose logs -f web`
        - Rails console: `podman compose exec web rails c`
        - Database: `podman compose exec web rails dbconsole`
      SKILL
    },

    'data_analysis' => {
      name: 'Data Analysis',
      keywords: %w[analyze data chart graph report metrics statistics],
      source: 'built-in',
      content: <<~SKILL.strip
        ## Data Analysis Skill
        
        ### Approach
        1. UNDERSTAND: What question are we answering?
        2. GATHER: Collect relevant data
        3. CLEAN: Handle missing/invalid values
        4. ANALYZE: Apply appropriate methods
        5. VISUALIZE: Present findings clearly
        
        ### Best Practices
        - State assumptions explicitly
        - Show sample data before full analysis
        - Explain statistical methods used
        - Provide actionable insights
      SKILL
    },

    'workflow_building' => {
      name: 'Workflow Building',
      keywords: %w[workflow automation automate trigger when then flow sequence drip],
      source: 'built-in',
      content: <<~SKILL.strip
        ## Workflow Building Skill
        
        Workflows are visual automations with triggers → actions → outputs.
        
        ### Key Canvases
        - `workflow_designer` — Visual drag-drop builder
        - `automation_dashboard` — Monitor all automations
        
        ### Trigger Types
        - form_submission, schedule (cron), event, webhook, manual
        
        ### Common Actions
        - send_email, update_record, call_integration, add_to_group, delay
        
        ### Quick Start
        ```
        load_canvas(canvas_name: "workflow_designer")
        ```
        
        Or create programmatically:
        ```
        platform_create(type: "workflow", data: {
          name: "Welcome Flow",
          trigger_type: "form_submission",
          status: "draft"
        })
        ```
        
        Use `platform_query(type: "automation_recipes")` to see pre-built templates.
      SKILL
    },

    'app_building' => {
      name: 'Application Building',
      keywords: %w[app application module custom build crud database schema],
      source: 'built-in',
      content: <<~SKILL.strip
        ## Application Building Skill
        
        Custom apps extend the platform with domain-specific data and views.
        
        ### Key Canvases
        - `module_manager` — List and manage all custom modules
        - `module_marketplace` — Discover pre-built modules
        
        ### Schema Field Types
        text, textarea, number, currency, date, datetime, select, 
        multi_select, boolean, reference, file, json
        
        ### Quick Start
        ```
        platform_create(type: "app_module", data: {
          name: "Project Tracker",
          slug: "projects",
          schema: {
            fields: [
              { name: "title", type: "text", required: true },
              { name: "status", type: "select", options: ["open", "done"] }
            ]
          }
        })
        ```
        
        After creation, view with:
        ```
        load_canvas(canvas_name: "module_manager")
        ```
        
        Reference fields create relationships between objects.
      SKILL
    },

    'landing_page_building' => {
      name: 'Landing Page Building',
      keywords: %w[landing page website design hero cta section build create],
      source: 'built-in',
      content: <<~SKILL.strip
        ## Landing Page Building Skill
        
        ### Key Canvases
        - `landing_page_editor` — Create and edit landing pages
        - `my_creations` — View all created assets
        
        ### Quick Start — Create a new page
        ```
        platform_create(type: "landing_page", data: { title: "My Page", description: "..." })
        ```
        
        Then show the editor:
        ```
        load_canvas(canvas_name: "landing_page_editor", canvas_data: { landing_page_id: ID })
        ```
        
        ### Edit Existing
        ```
        load_canvas(canvas_name: "landing_page_editor", canvas_data: { landing_page_id: 42 })
        ```
        
        ### Query Pages
        ```
        platform_query(type: "landing_pages", filters: { status: "published" })
        ```
      SKILL
    }
  }.freeze

  # ═══════════════════════════════════════════════════════════════
  # PRIVATE METHODS
  # ═══════════════════════════════════════════════════════════════

  private_class_method def self.get_integration_skill(integration_name)
    name_lower = integration_name.to_s.downcase

    # DB first: check for a SystemSkill record (AMOS can evolve these)
    db_skill = SystemSkill.active.find_integration_skill(name_lower) rescue nil
    if db_skill
      return {
        name: db_skill.name,
        content: db_skill.content,
        source: db_skill.source,
        type: :integration,
        integration: name_lower,
        system_skill_id: db_skill.id
      }
    end

    # Fallback: hardcoded constant (used before skills are seeded)
    skill_data = INTEGRATION_SKILLS[name_lower]
    return nil unless skill_data

    {
      name: skill_data[:name],
      content: skill_data[:content],
      source: skill_data[:source],
      type: :integration,
      integration: name_lower
    }
  end

  private_class_method def self.get_canvas_skill(canvas_context)
    nil
  end

  private_class_method def self.detect_skills_from_message(message)
    return [] if message.blank?

    msg_lower = message.downcase
    skills = []

    # DB first: check SystemSkill task skills
    begin
      db_task_skills = SystemSkill.active.task_skills.global
      db_task_skills.each do |db_skill|
        if db_skill.keywords.any? { |kw| msg_lower.include?(kw.downcase) }
          skills << {
            name: db_skill.name,
            content: db_skill.content,
            source: db_skill.source,
            type: :task,
            system_skill_id: db_skill.id
          }
        end
      end
    rescue => e
      Rails.logger.debug "[SkillLibrary] DB task skill lookup failed (#{e.message}), using constants"
    end

    # If no DB skills found, fall back to constants
    if skills.empty?
      TASK_SKILLS.each do |_key, skill_data|
        if skill_data[:keywords].any? { |kw| msg_lower.include?(kw) }
          skills << {
            name: skill_data[:name],
            content: skill_data[:content],
            source: skill_data[:source],
            type: :task
          }
        end
      end
    end

    skills
  end

  private_class_method def self.search_custom_skills(message:, entity:, limit:)
    # Search entity's custom uploaded skills (from AgentPlugin with skill_format)
    # These are skills imported via SkillFileImporterService
    
    custom_skills = AgentPlugin.where(entity: entity)
                               .where("configuration->>'skill_format' = ?", 'claude_skill_md')
    
    return [] if custom_skills.empty?
    
    msg_lower = message.downcase
    msg_words = msg_lower.split(/\W+/).reject { |w| w.length < 3 }
    
    custom_skills.filter_map do |plugin|
      relevance = 0

      # Priority 1: Match against "use_when" conditions (highest signal)
      # These are the "Use this skill when:" bullets extracted during import
      use_when = plugin.configuration&.dig('use_when') || []
      if use_when.any?
        use_when.each do |condition|
          condition_words = condition.downcase.split(/\W+/).reject { |w| w.length < 3 }
          match_count = condition_words.count { |w| msg_lower.include?(w) }
          # If >50% of a condition's words match, it's a strong signal
          if condition_words.any? && match_count.to_f / condition_words.length > 0.5
            relevance += 10 + match_count
          end
        end
      end

      # Priority 2: Match against name + description (weaker signal)
      skill_text = "#{plugin.name} #{plugin.description}".downcase
      relevance += msg_words.count { |w| skill_text.include?(w) }
      
      next nil if relevance == 0
      
      prompt_text = plugin.system_prompt.is_a?(Hash) ? 
                    plugin.system_prompt['prompt'] : 
                    plugin.system_prompt.to_s
      
      {
        name: plugin.name,
        content: prompt_text,
        source: 'custom',
        type: :custom,
        plugin_id: plugin.id,
        relevance: relevance
      }
    end.sort_by { |s| -s[:relevance] }.first(limit)
  end

  private_class_method def self.build_skill_block(skills)
    return nil if skills.empty?
    
    blocks = skills.map do |skill|
      <<~BLOCK
        ### 📚 #{skill[:name]}
        #{skill[:content]}
      BLOCK
    end
    
    <<~COMBINED
      ## 🎓 RELEVANT SKILLS
      
      The following expertise has been loaded to help with this task:
      
      #{blocks.join("\n---\n\n")}
    COMBINED
  end
end
