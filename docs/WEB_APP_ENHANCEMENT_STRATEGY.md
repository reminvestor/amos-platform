# Web App Enhancement Strategy
## Making Web Apps Beautiful, Powerful, and Fully Integrated

*Created: 2026-01-17*

---

## 🔍 Current State Analysis

### What We Have

| Component | Status | Notes |
|-----------|--------|-------|
| **Bootstrap 5** | ✅ Integrated | CDN in landing pages, SCSS in app |
| **Landing Page Compiler** | ✅ Working | Generates Bootstrap HTML |
| **Design Agent** | ⚠️ Basic | Only generates colors/fonts |
| **ETL Pipeline** | ✅ Excellent | AI generates code → runs deterministically |
| **Transform Code Executor** | ✅ Excellent | Sandboxed Ruby execution |
| **Workflow Engine** | ✅ Working | Parallel execution, step types |
| **Website/WebApp Models** | ✅ New | From Platform Factory redesign |

### What's Missing (The Gaps)

1. **🎨 Frontend Design Intelligence** - No sophisticated design agent with Bootstrap mastery
2. **📦 Component Library** - No pre-built, reusable Bootstrap components
3. **⚡ Deterministic Automations** - Using LLMs where simple code would work
4. **🎭 Theme System** - Web apps lack cohesive theming
5. **📜 JS/CSS Asset Management** - No framework for custom scripts/styles
6. **🔐 Automation Code Sandbox** - ETL has it, web apps don't

---

## 🎯 The Core Insight

> **"AI for SETUP, Code for EXECUTION"**

The iPaaS ETL pipeline does this perfectly:

```
┌─────────────────────────────────────────────────────────────────┐
│ SETUP TIME (AI)                  │ EXECUTION TIME (No AI)      │
├──────────────────────────────────┼─────────────────────────────┤
│ 1. User describes transformation │ 1. Record arrives           │
│ 2. AI generates Ruby code        │ 2. Code executes in sandbox │
│ 3. Code is tested & saved        │ 3. Data transformed         │
│ 4. User approves                 │ 4. Result stored            │
└──────────────────────────────────┴─────────────────────────────┘
```

**This same pattern should apply to ALL web app automations!**

---

## 🏗️ Proposed Architecture

### 1. Frontend Design Intelligence (New Agent)

Replace the basic `DesignAgent` with a sophisticated `FrontendDesignExpert`:

```ruby
# app/services/agents/frontend_design_expert.rb
class FrontendDesignExpert
  BOOTSTRAP_COMPONENT_LIBRARY = {
    # Pre-built, tested Bootstrap 5 components
    hero: {
      variants: [:gradient, :image_bg, :video_bg, :minimal, :split],
      customizable: [:colors, :layout, :cta_style, :animation]
    },
    features: {
      variants: [:cards, :icons, :alternating, :timeline],
      customizable: [:columns, :icon_style, :card_style]
    },
    testimonials: {
      variants: [:carousel, :grid, :quote_blocks, :video],
      customizable: [:avatar_style, :rating_display]
    },
    pricing: {
      variants: [:cards, :table, :toggle_annual],
      customizable: [:highlight_plan, :feature_comparison]
    },
    forms: {
      variants: [:inline, :stacked, :wizard, :floating_labels],
      customizable: [:validation_style, :submit_animation]
    },
    navigation: {
      variants: [:sticky, :transparent, :sidebar, :mega_menu],
      customizable: [:logo_position, :cta_button]
    },
    footer: {
      variants: [:simple, :multi_column, :centered, :dark],
      customizable: [:social_icons, :newsletter]
    }
  }

  DESIGN_SYSTEMS = {
    modern: { font: 'Inter', corners: 'rounded-3', shadows: true },
    minimal: { font: 'DM Sans', corners: 'rounded-0', shadows: false },
    corporate: { font: 'Source Sans Pro', corners: 'rounded-1', shadows: true },
    playful: { font: 'Nunito', corners: 'rounded-pill', shadows: true },
    elegant: { font: 'Playfair Display', corners: 'rounded-2', shadows: false }
  }

  # Generate complete, production-ready Bootstrap HTML
  def design_component(type:, variant:, customizations:, content:)
    template = load_template(type, variant)
    apply_customizations(template, customizations)
    inject_content(template, content)
    optimize_for_mobile(template)
  end
end
```

### 2. Component Library System

Create a library of tested, beautiful Bootstrap components:

```
app/views/components/
├── bootstrap/
│   ├── heroes/
│   │   ├── _gradient.html.erb
│   │   ├── _image_bg.html.erb
│   │   └── _split.html.erb
│   ├── features/
│   │   ├── _icon_cards.html.erb
│   │   ├── _alternating.html.erb
│   │   └── _timeline.html.erb
│   ├── testimonials/
│   │   ├── _carousel.html.erb
│   │   └── _quote_blocks.html.erb
│   ├── pricing/
│   │   ├── _cards.html.erb
│   │   └── _comparison.html.erb
│   ├── forms/
│   │   ├── _wizard.html.erb
│   │   └── _floating_labels.html.erb
│   └── navigation/
│       ├── _sticky.html.erb
│       └── _mega_menu.html.erb
└── web_app/
    ├── dashboards/
    │   ├── _stats_cards.html.erb
    │   └── _activity_feed.html.erb
    ├── data_views/
    │   ├── _data_table.html.erb
    │   └── _kanban_board.html.erb
    └── auth/
        ├── _login_form.html.erb
        └── _registration_wizard.html.erb
```

### 3. Deterministic Automation System

**New Model: `AutomationCode`**

Just like `transform_code` for ETL, but for web app automations:

```ruby
# db/migrate/xxx_create_automation_codes.rb
create_table :automation_codes do |t|
  t.references :entity, null: false
  t.references :web_app, null: true
  t.references :app_module, null: true
  t.string :name, null: false
  t.string :trigger_type  # 'record_created', 'record_updated', 'schedule', 'webhook', 'form_submit'
  t.jsonb :trigger_config # { field: 'status', from: 'draft', to: 'published' }
  
  # The AI-generated code
  t.text :code, null: false
  t.integer :code_version, default: 1
  t.datetime :code_generated_at
  t.string :code_generated_by  # 'claude-sonnet-4-20250514'
  
  # Testing/validation
  t.jsonb :sample_input
  t.jsonb :sample_output
  t.boolean :is_tested, default: false
  t.datetime :last_tested_at
  
  # Execution tracking
  t.integer :execution_count, default: 0
  t.integer :error_count, default: 0
  t.datetime :last_executed_at
  t.datetime :last_error_at
  t.text :last_error_message
  
  t.string :status, default: 'draft'  # draft, testing, active, paused, failed
  t.timestamps
end
```

**AutomationCodeExecutor** (like TransformCodeExecutor):

```ruby
# app/services/automation_code_executor.rb
class AutomationCodeExecutor
  TIMEOUT_SECONDS = 10
  
  def initialize(automation_code, context = {})
    @automation = automation_code
    @context = context
  end

  def execute!(trigger_data)
    return { success: false, error: 'Automation not active' } unless @automation.active?

    sandbox = AutomationSandbox.new(
      code: @automation.code,
      trigger_data: trigger_data,
      context: build_context
    )

    result = sandbox.execute
    @automation.record_execution!(result)
    result
  rescue => e
    @automation.record_error!(e)
    { success: false, error: e.message }
  end

  private

  def build_context
    AutomationContext.new(
      entity: @automation.entity,
      web_app: @automation.web_app,
      app_module: @automation.app_module,
      user: @context[:user],
      trigger_data: @context[:trigger_data]
    )
  end
end
```

**AutomationContext** (safe helpers for automation code):

```ruby
# app/services/automation_context.rb
class AutomationContext
  attr_reader :entity, :web_app, :app_module, :user, :trigger_data

  # ============================================
  # SAFE HELPERS FOR AUTOMATION CODE
  # ============================================

  # Data Operations (read-only by default)
  def find_record(model_slug, id)
    model = app_module&.dynamic_model
    return nil unless model
    model.find_by(id: id)
  end

  def query_records(model_slug, conditions = {})
    model = app_module&.dynamic_model
    return [] unless model
    model.where(conditions).limit(100)
  end

  def create_record(model_slug, attributes)
    # Only allowed if explicitly enabled
    raise "Create not allowed" unless @allow_writes
    model = app_module&.dynamic_model
    model.create!(attributes.merge(entity_id: entity.id))
  end

  def update_record(model_slug, id, attributes)
    raise "Update not allowed" unless @allow_writes
    model = app_module&.dynamic_model
    record = model.find(id)
    record.update!(attributes)
  end

  # Notifications
  def send_email(to:, subject:, body:)
    AutomationMailer.custom_notification(to, subject, body).deliver_later
  end

  def send_slack_message(channel:, message:)
    connection = entity.integration_connections.find_by(integration_slug: 'slack')
    return { success: false, error: 'Slack not connected' } unless connection
    SlackNotifier.new(connection).post(channel: channel, text: message)
  end

  def create_hub_notification(user_id:, message:, type: 'info')
    HubNotification.create!(entity: entity, user_id: user_id, message: message, notification_type: type)
  end

  # External API calls (allowlisted domains only)
  def http_get(url, headers: {})
    validate_url!(url)
    HTTParty.get(url, headers: headers, timeout: 5)
  end

  def http_post(url, body:, headers: {})
    validate_url!(url)
    HTTParty.post(url, body: body.to_json, headers: headers.merge('Content-Type' => 'application/json'), timeout: 5)
  end

  # Date/Time
  def now; Time.current; end
  def today; Date.current; end
  def days_from_now(n); n.days.from_now; end
  def days_ago(n); n.days.ago; end

  # String/Number helpers (same as TransformContext)
  def titleize(str); str.to_s.titleize; end
  def format_currency(cents); ActionController::Base.helpers.number_to_currency(cents / 100.0); end
  def format_date(date, format = '%B %d, %Y'); date&.strftime(format); end

  # Logging
  def log(message)
    Rails.logger.info "[AutomationCode:#{@automation.id}] #{message}"
  end

  private

  def validate_url!(url)
    allowed_domains = entity.settings['allowed_automation_domains'] || []
    allowed_domains += ['api.stripe.com', 'api.slack.com', 'api.hubspot.com']
    
    uri = URI.parse(url)
    unless allowed_domains.any? { |d| uri.host&.end_with?(d) }
      raise "Domain not allowed: #{uri.host}"
    end
  end
end
```

### 4. Generate Automation Code Tool

```ruby
# app/services/tools/generate_automation_code_tool.rb
class GenerateAutomationCodeTool < BaseTool
  def self.metadata
    {
      name: "generate_automation_code",
      description: "Generate deterministic Ruby automation code. AI writes the code once during setup, then it runs WITHOUT AI - fast and predictable.",
      category: "automation",
      input_schema: {
        type: "object",
        properties: {
          name: { type: "string", description: "Name for this automation" },
          trigger_type: { 
            type: "string", 
            enum: ["record_created", "record_updated", "status_changed", "schedule", "webhook", "form_submit"],
            description: "What triggers this automation"
          },
          trigger_config: { type: "object", description: "Trigger configuration (e.g., { field: 'status', from: 'draft', to: 'published' })" },
          action_description: { type: "string", description: "Natural language description of what should happen" },
          app_module_id: { type: "integer", description: "Optional: AppModule this automation is for" },
          web_app_id: { type: "integer", description: "Optional: WebApp this automation is for" }
        },
        required: ["name", "trigger_type", "action_description"]
      }
    }
  end

  def execute(args)
    # 1. Generate the code using AI
    code = generate_code(args)
    return error_response(code[:error]) unless code[:success]

    # 2. Create the automation record
    automation = AutomationCode.create!(
      entity: entity,
      web_app_id: args['web_app_id'],
      app_module_id: args['app_module_id'],
      name: args['name'],
      trigger_type: args['trigger_type'],
      trigger_config: args['trigger_config'] || {},
      code: code[:code],
      code_generated_at: Time.current,
      code_generated_by: 'claude-sonnet-4-20250514',
      status: 'testing'
    )

    # 3. Test with sample data
    test_result = test_automation(automation)

    if test_result[:success]
      automation.update!(is_tested: true, last_tested_at: Time.current, sample_output: test_result[:output])
      success_response(
        automation_id: automation.id,
        message: "Automation '#{automation.name}' created and tested successfully!",
        code_preview: code[:code].truncate(500),
        test_output: test_result[:output],
        next_step: "Activate this automation when you're ready: automation.activate!"
      )
    else
      automation.update!(status: 'draft')
      error_response("Code generated but test failed: #{test_result[:error]}. Please refine the action description.")
    end
  end

  private

  def generate_code(args)
    prompt = <<~PROMPT
      Generate Ruby automation code for the following:

      TRIGGER: #{args['trigger_type']}
      #{args['trigger_config'].present? ? "TRIGGER CONFIG: #{args['trigger_config'].to_json}" : ''}
      
      ACTION: #{args['action_description']}

      AVAILABLE HELPERS:
      - find_record(model_slug, id) - Find a record
      - query_records(model_slug, conditions) - Query records
      - create_record(model_slug, attributes) - Create a record
      - update_record(model_slug, id, attributes) - Update a record
      - send_email(to:, subject:, body:) - Send email
      - send_slack_message(channel:, message:) - Post to Slack
      - create_hub_notification(user_id:, message:, type:) - Create Hub notification
      - http_get(url, headers:) - GET request
      - http_post(url, body:, headers:) - POST request
      - now, today, days_from_now(n), days_ago(n) - Date/time
      - titleize, format_currency, format_date - Formatting
      - log(message) - Log a message

      The code receives `trigger_data` hash with the trigger event data.
      Return ONLY the Ruby code in ```ruby blocks.
    PROMPT

    response = BedrockService.new.chat(
      messages: [{ role: 'user', content: prompt }],
      system: automation_system_prompt,
      model: 'claude-sonnet-4-20250514',
      temperature: 0.2
    )

    code = extract_code(response[:content])
    code.present? ? { success: true, code: code } : { success: false, error: "Failed to generate code" }
  end

  def automation_system_prompt
    <<~PROMPT
      You generate Ruby automation code. The code will run WITHOUT AI after generation.
      
      RULES:
      1. Use ONLY the provided helpers
      2. Handle errors gracefully
      3. Keep code simple and readable
      4. Log important actions
      5. Return a hash with { success: true/false, message: "..." }
      
      OUTPUT: Only Ruby code in ```ruby blocks. No explanations.
    PROMPT
  end
end
```

### 5. Theme System for Web Apps

```ruby
# app/models/web_app_theme.rb
class WebAppTheme < ApplicationRecord
  belongs_to :web_app

  PRESETS = {
    light_modern: {
      colors: {
        primary: '#0d6efd',
        secondary: '#6c757d',
        success: '#198754',
        background: '#ffffff',
        surface: '#f8f9fa',
        text: '#212529',
        text_muted: '#6c757d'
      },
      typography: {
        font_family: "'Inter', sans-serif",
        heading_font: "'Inter', sans-serif",
        base_size: '16px',
        heading_weight: 600
      },
      components: {
        border_radius: '0.375rem',
        shadow_sm: '0 0.125rem 0.25rem rgba(0, 0, 0, 0.075)',
        shadow: '0 0.5rem 1rem rgba(0, 0, 0, 0.15)',
        button_style: 'filled'  # filled, outline, gradient
      }
    },
    dark_modern: {
      colors: {
        primary: '#0d6efd',
        secondary: '#6c757d',
        background: '#1a1a2e',
        surface: '#16213e',
        text: '#eaeaea',
        text_muted: '#a0a0a0'
      },
      # ...
    },
    corporate: { ... },
    startup: { ... },
    elegant: { ... }
  }

  def generate_css
    <<~CSS
      :root {
        --primary: #{colors['primary']};
        --secondary: #{colors['secondary']};
        --background: #{colors['background']};
        --surface: #{colors['surface']};
        --text: #{colors['text']};
        --text-muted: #{colors['text_muted']};
        
        --font-family: #{typography['font_family']};
        --heading-font: #{typography['heading_font']};
        --base-size: #{typography['base_size']};
        
        --border-radius: #{components['border_radius']};
        --shadow-sm: #{components['shadow_sm']};
        --shadow: #{components['shadow']};
      }
      
      body {
        font-family: var(--font-family);
        font-size: var(--base-size);
        color: var(--text);
        background-color: var(--background);
      }
      
      /* Bootstrap overrides using CSS variables */
      .btn-primary {
        background-color: var(--primary);
        border-color: var(--primary);
      }
      
      .card {
        background-color: var(--surface);
        border-radius: var(--border-radius);
        box-shadow: var(--shadow-sm);
      }
      
      /* ... more component overrides ... */
    CSS
  end
end
```

### 6. JS Asset Management

```ruby
# app/models/web_app_script.rb
class WebAppScript < ApplicationRecord
  belongs_to :web_app
  
  # Types: inline, external_url, npm_package
  # Locations: head, body_start, body_end
  
  SAFE_LIBRARIES = {
    'alpinejs' => 'https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js',
    'htmx' => 'https://unpkg.com/htmx.org@1.9.x',
    'chart.js' => 'https://cdn.jsdelivr.net/npm/chart.js@4.x.x',
    'sortablejs' => 'https://cdn.jsdelivr.net/npm/sortablejs@1.x.x',
    'flatpickr' => 'https://cdn.jsdelivr.net/npm/flatpickr@4.x.x'
  }

  def render_tag
    case script_type
    when 'external_url'
      %(<script src="#{url}" #{defer? ? 'defer' : ''}></script>)
    when 'inline'
      %(<script>#{content}</script>)
    when 'npm_package'
      %(<script src="#{SAFE_LIBRARIES[package_name]}"></script>)
    end
  end
end
```

---

## 📊 Implementation Roadmap

### Phase 1: Deterministic Automations (Week 1-2)
- [ ] Create `AutomationCode` model and migrations
- [ ] Implement `AutomationCodeExecutor` with sandbox
- [ ] Implement `AutomationContext` with safe helpers
- [ ] Create `generate_automation_code` tool
- [ ] Add triggers: record events, schedules, webhooks

### Phase 2: Frontend Design Intelligence (Week 2-3)
- [ ] Expand `FrontendDesignExpert` with Bootstrap mastery
- [ ] Build component library (20+ components)
- [ ] Create design system presets
- [ ] Add component picker UI for canvas

### Phase 3: Theme & Asset System (Week 3-4)
- [ ] Implement `WebAppTheme` model
- [ ] Create theme builder UI
- [ ] Implement `WebAppScript` model
- [ ] Add safe external library integration

### Phase 4: Integration & Polish (Week 4-5) - ✅ COMPLETE
- [x] Connect automations to web app form submissions (AutomationBridge.on_form_submit)
- [x] Connect automations to module record events (AutomationBridge + AutomationTriggerable)
- [x] Add automation monitoring dashboard (_automation_dashboard.html.erb)
- [x] Create "Automation Recipes" (12 pre-built patterns across 5 categories)

---

## 🎯 Key Principles

1. **"AI for SETUP, Code for EXECUTION"**
   - AI helps write the code
   - Code runs fast, deterministically, without AI

2. **"Bootstrap First"**
   - All components are Bootstrap 5 native
   - Factory knows all Bootstrap classes
   - Consistent, tested, mobile-responsive

3. **"Beautiful by Default"**
   - Pre-built components look professional
   - Theme system ensures cohesion
   - Design agent has taste, not just function

4. **"Ecosystem Citizens"**
   - Web apps connect to Hub
   - Automations trigger workflows
   - Modules sync with integrations

5. **"Determinism Where Possible"**
   - LLMs are expensive and slow
   - Simple automations should be fast
   - Complex reasoning still uses AI

---

## 💡 Example: Knowledge Base with Deterministic Automations

```ruby
# User: "Build me a knowledge base that sends Slack notifications when articles are published"

# ApplicationPlan creates:
plan = {
  modules: [{
    name: 'Articles',
    fields: ['title', 'content', 'status', 'author'],
    status_workflow: ['draft', 'review', 'published']
  }],
  
  web_app: {
    name: 'KB Portal',
    requires_auth: true,
    theme_preset: 'light_modern'
  },
  
  automations: [{
    name: 'Notify on Publish',
    trigger_type: 'status_changed',
    trigger_config: { field: 'status', to: 'published' },
    # AI generates this code ONCE during setup:
    code: <<~RUBY
      def execute(trigger_data)
        article = trigger_data[:record]
        
        # Send Slack notification
        send_slack_message(
          channel: '#content-team',
          message: "📚 New article published: *#{article[:title]}*\\nBy: #{article[:author]}"
        )
        
        # Create Hub notification for the author
        create_hub_notification(
          user_id: article[:created_by_id],
          message: "Your article '#{article[:title]}' is now live!",
          type: 'success'
        )
        
        log("Published article #{article[:id]} - notifications sent")
        { success: true, message: 'Notifications sent' }
      end
    RUBY
  }]
}

# When an article is published:
# 1. Status changes to 'published'
# 2. AutomationTriggerJob fires
# 3. AutomationCodeExecutor.new(automation).execute!(trigger_data)
# 4. Code runs in sandbox - NO AI CALL
# 5. Slack message sent, Hub notification created
# 6. < 100ms total execution time
```

---

## ✅ Summary: What We're Adding

| Gap | Solution | Priority | Status |
|-----|----------|----------|--------|
| LLM overuse for simple automation | `AutomationCode` + `AutomationCodeExecutor` | 🔴 HIGH | ✅ DONE |
| Basic design agent | `FrontendDesignExpert` with Bootstrap mastery | 🔴 HIGH | ✅ DONE |
| No component library | Pre-built Bootstrap component templates | 🟡 MEDIUM | ✅ DONE |
| No theme system | `WebAppTheme` with CSS variable generation | 🟡 MEDIUM | ✅ DONE |
| No JS library support | `WebAppScript` with safe external libs | 🟢 LOW | Pending |

**Bottom Line**: The ETL pattern is brilliant - extend it to all web app automations. Add a sophisticated design agent that truly understands Bootstrap. Make web apps beautiful AND fast.

---

## 🎉 IMPLEMENTATION STATUS

### Phase 1: Deterministic Automations - ✅ COMPLETE

**Commit:** `a6d948cb` - 3,110 lines added

**Files Created:**

| File | Lines | Purpose |
|------|-------|---------|
| `db/migrate/20260117210000_create_automation_codes.rb` | 75 | Migration for automation_codes & automation_executions |
| `app/models/automation_code.rb` | 280 | Model with state machine, trigger matching, stats |
| `app/models/automation_execution.rb` | 90 | Audit trail for each execution |
| `app/services/automation_context.rb` | 420 | 50+ safe helpers (data, notifications, HTTP, etc.) |
| `app/services/automation_sandbox.rb` | 200 | Secure code execution with timeout/size limits |
| `app/services/automation_code_executor.rb` | 150 | Main execution entry point |
| `app/services/tools/generate_automation_code_tool.rb` | 230 | AI generates Ruby code from natural language |
| `app/jobs/automation_trigger_job.rb` | 120 | Background job for async execution |

**Test Coverage:**

| File | Tests | Coverage |
|------|-------|----------|
| `test/models/automation_code_test.rb` | 25+ | Validations, status, triggers, scopes |
| `test/services/automation_sandbox_test.rb` | 20+ | Helpers, errors, timeout, security |
| `test/integration/automation_code_e2e_test.rb` | 15+ | Full lifecycle, matching, audit trail |
| `test/fixtures/automation_codes.yml` | 5 | Various states and trigger types |
| `test/fixtures/automation_executions.yml` | 3 | Success, failure, test executions |

**Usage Example:**

```ruby
# 1. Create automation (AI generates code)
automation = AutomationCode.create!(
  entity: entity,
  name: 'Notify on Publish',
  trigger_type: 'status_changed',
  trigger_config: { from: 'draft', to: 'published' },
  code: <<~RUBY
    def execute(trigger_data)
      send_slack_message(
        channel: '#content',
        message: "📚 Published: #{record[:title]}"
      )
      { success: true, message: 'Notified' }
    end
  RUBY
)

# 2. Test it
automation.test!  # Runs in sandbox, updates is_tested

# 3. Activate it
automation.activate!

# 4. It fires automatically when records change
# OR trigger manually:
AutomationTriggerJob.perform_later(automation.id, trigger_data)
```

---

### Phase 2: Design Space & Frontend Intelligence - ✅ COMPLETE

**Commit:** `1745dd82` - 2,850 lines added

**The Vision:**
A unified Design Space where users can build web apps, websites, and landing pages with visual feedback, AI assistance, and real-time preview.

**New Space:**

| Component | Description |
|-----------|-------------|
| `SpaceDefinition::DESIGN` | New space type alongside Personal/Work/Team |
| Custom Context Prompt | Design-focused AI behavior |
| Curated Tool Loadout | Building & design tools only |
| Design Menu Items | web_apps, websites, landing_pages, modules, automations, workflows, components |

**Frontend Design Expert Agent:**

| Component Category | Variants |
|-------------------|----------|
| Hero Sections | gradient, image_bg, split, minimal, video_bg |
| Features | icon_cards, alternating, timeline, tabs |
| Testimonials | carousel, quote_cards, video, logo_bar |
| Pricing | cards, comparison, toggle |
| Forms | inline, stacked, wizard, floating |
| Navigation | sticky, transparent, sidebar, mega_menu |
| Footer | simple, multi_column, centered, newsletter |
| CTA | banner, card, floating |

**Design Systems (Themes):**

| Theme | Font | Primary | Best For |
|-------|------|---------|----------|
| Modern | Inter | #3b82f6 | SaaS, tech startups |
| Minimal | DM Sans | #000000 | Portfolios, agencies |
| Corporate | Source Sans Pro | #1e40af | B2B, enterprise |
| Playful | Nunito | #8b5cf6 | Consumer apps, education |
| Elegant | Playfair Display | #78350f | Luxury, fashion |
| Dark Mode | Space Grotesk | #60a5fa | Dev tools, creative |

**Visual Canvases:**

| Canvas | Features |
|--------|----------|
| `_design_preview.html.erb` | iFrame preview, viewport switching (desktop/tablet/mobile), edit mode, save/discard |
| `_workflow_editor.html.erb` | Flow diagram, color-coded nodes, node palette, automations grid |
| `_component_gallery.html.erb` | Category sidebar, design system selector, preview modal, use buttons |

**Key Tool:**

| Tool | Purpose |
|------|---------|
| `load_design_canvas` | Unified loader for all design canvases, extracts workflow nodes from automations |

**Tests:**

| File | Tests |
|------|-------|
| `test/services/frontend_design_expert_test.rb` | 20+ tests for components, themes, CSS generation |
| `test/integration/design_space_test.rb` | 15+ tests for space config, tools, canvases |

**Usage:**

```ruby
# In Design Space, Amos can:

# 1. Show component gallery
load_design_canvas(canvas_type: 'component_gallery', category: 'hero', design_system: 'modern')

# 2. Preview a web app in iFrame
load_design_canvas(canvas_type: 'design_preview', preview_url: '/web_apps/my-app', edit_mode: true)

# 3. Show workflow editor for an automation
load_design_canvas(canvas_type: 'workflow_editor', workflow_id: 123)

# 4. Get design recommendations
Agents::FrontendDesignExpert.recommend_design_system(business_type: 'saas')
# => [{key: :modern, name: 'Modern', ...}, {key: :dark_mode, ...}]

# 5. Generate CSS for theming
Agents::FrontendDesignExpert.generate_css_variables(:modern)
# => ":root { --bs-primary: #3b82f6; ... }"
```

---

### Phase 2.5: Remaining Infrastructure - ✅ COMPLETE

**Commit:** `e2dcc387` - 1,523 lines added

| Component | Description |
|-----------|-------------|
| `WebAppScript` model | Secure JS library management with 20+ allowlisted CDN libs |
| 7 Component Templates | Hero, features, testimonials, pricing, forms, CTA |
| `DesignPreviewController` | 6 preview endpoints for iFrame rendering |
| Preview layout & views | Bootstrap 5 + Lucide + edit mode support |
| Routes | `/design_preview/*` endpoints |

---

### Phase 3: Integration Layer - ✅ COMPLETE

**Commit:** `9f923364` - 1,018 lines added

**The Missing Piece: Connecting Everything Together**

| Service | Purpose |
|---------|---------|
| `Modules::AutomationBridge` | Connects module events to automation triggers |
| `AutomationTriggerable` concern | Mixin for auto-triggering on create/update/status |
| `DesignSpaceService` | High-level orchestration for entire design flow |

**AutomationBridge Events:**

```ruby
# When module records change, automations fire automatically:
Modules::AutomationBridge.on_record_created(record, user)
Modules::AutomationBridge.on_record_updated(record, changes, user)
Modules::AutomationBridge.on_status_changed(record, 'draft', 'published', user)
Modules::AutomationBridge.on_form_submit(form_data, entity, user)
Modules::AutomationBridge.on_webhook(payload, entity, path)
```

**DesignSpaceService API:**

```ruby
service = DesignSpaceService.new(user, entity, session_id)

# Start building
service.start_design_session(name: 'CRM', description: '...', type: 'web_app')
service.update_design_plan(plan_id: 1, updates: {...})
service.build_approved_plan(plan_id: 1)

# Components
service.get_component_recommendations(section_type: 'hero', business_type: 'saas')
service.generate_component(type: 'pricing', variant: 'cards', data: {...})

# Automations
service.create_automation(name: '...', description: '...', trigger_type: 'status_changed')
service.test_automation(automation_id: 1, test_data: {...})

# Previews
service.load_preview(type: 'web_app', id_or_slug: 1, edit_mode: true)
```

**The Complete Flow:**

```
┌─────────────────────────────────────────────────────────────────┐
│                     THE COMPLETE FLOW                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. User enters Design Space                                     │
│     └─> SpaceDefinition::DESIGN                                  │
│                                                                  │
│  2. "Build me a customer portal"                                 │
│     └─> DesignSpaceService.start_design_session                  │
│         └─> ApplicationPlannerService.create_plan                │
│                                                                  │
│  3. Plan displayed in canvas                                     │
│     └─> broadcast_to_canvas('application_plan_preview')          │
│                                                                  │
│  4. User reviews & requests changes                              │
│     └─> DesignSpaceService.update_design_plan                    │
│                                                                  │
│  5. "Build it!"                                                  │
│     └─> ApplicationBuildService.execute! (transactional)         │
│         ├─> AppModule created                                    │
│         ├─> AgentPlugin created                                  │
│         ├─> ToolDefinitions created                              │
│         ├─> AutomationCodes created                              │
│         └─> Website/WebApp created                               │
│                                                                  │
│  6. Preview loads in iFrame                                      │
│     └─> /design_preview/web_app/:id                              │
│                                                                  │
│  7. User creates records in module                               │
│     └─> AutomationTriggerable fires                              │
│         └─> AutomationBridge.on_record_created                   │
│             └─> AutomationTriggerJob.perform_later               │
│                 └─> AutomationCodeExecutor.execute               │
│                     └─> Slack notification sent (no LLM!)        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Tests:** 25+ end-to-end tests covering the entire flow

---

### Phase 4: Integration & Polish - ✅ COMPLETE

**Commit:** `[Phase 4]` - Monitoring & Recipes

**Automation Monitoring Dashboard:**

A full-featured dashboard showing:
- Real-time stats: active automations, executions/24h, success rate, avg time
- List of all automations with status indicators
- Recent execution history with success/failure indicators
- Filter controls (all/active/paused)
- Action dropdowns (view, edit, test, pause/activate)
- Automation recipe suggestions

**Automation Recipes - 12 Pre-Built Patterns:**

| Category | Recipes |
|----------|---------|
| **Notifications** | Slack on status change, Email on create, Notify on assignment |
| **Data** | Update timestamp, Cascade status to children |
| **Integrations** | Webhook on event, Sync contact to CRM |
| **Workflows** | Approval workflow, SLA reminder |
| **Forms** | Process form submission |

**Recipe Features:**

```ruby
# List all recipes
AutomationRecipes.all

# Find specific recipe
AutomationRecipes.find('slack_on_status_change')

# Get suggestions for a module
AutomationRecipes.suggest_for_module(app_module)

# Apply a recipe with custom inputs
AutomationRecipes.apply(
  recipe_id: 'approval_workflow',
  entity: entity,
  user: user,
  inputs: { approver_role: 'manager' },
  app_module: tasks_module
)
```

**AutomationDashboardTool:**

```ruby
# View the monitoring dashboard
automation_dashboard(action: 'view_dashboard', show_recipes: true)

# List available recipes
automation_dashboard(action: 'list_recipes', category: 'notifications')

# Get suggestions for a module
automation_dashboard(action: 'get_suggestions', module_slug: 'orders')

# Apply a recipe
automation_dashboard(
  action: 'apply_recipe',
  recipe_id: 'slack_on_status_change',
  inputs: { slack_channel: '#sales' }
)
```

