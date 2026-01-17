# Platform Factory Deep Dive - Strategic Planning

> **Created**: January 17, 2026
> **Branch**: `feature/platform-factory-deep-dive`
> **Goal**: Make Platform Factory work reliably and design the website progression

---

## 🎯 Executive Summary

Platform Factory is the crown jewel of AMOS - the ability for AI to build complete, integrated applications through conversation. However, it's currently unreliable. This document outlines:

1. **Current State Analysis** - What's broken and why
2. **Platform Factory Redesign** - How to fix it
3. **Website Progression** - Landing Page → Website → Web App
4. **The Vision** - Building the future

---

## 📊 Current State Analysis

### What Platform Factory Should Do

```
User: "Build me a social media manager"
     ↓
┌─────────────────────────────────────────────────────────────────────┐
│                     PLATFORM FACTORY                                  │
├─────────────────────────────────────────────────────────────────────┤
│  1. START_MODULE_DESIGN - Create a design session                    │
│  2. PROPOSE_MODULE_SCHEMA - Design data model, integrations, etc.   │
│  3. User reviews preview canvas → approves                           │
│  4. APPROVE_MODULE_DESIGN - Generate all components                  │
│       ↓                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │ GENERATED COMPONENTS:                                            ││
│  │  • AppModule record (metadata, schema)                          ││
│  │  • Dynamic table in database                                    ││
│  │  • ModuleCanvas records (list, form, detail, dashboard)         ││
│  │  • ToolDefinition records (create_, update_, list_)             ││
│  │  • AgentPlugin (module expert agent)                            ││
│  │  • ScheduledAgentTask records                                   ││
│  │  • Workflow records                                             ││
│  │  • ModuleIntegration records                                    ││
│  └─────────────────────────────────────────────────────────────────┘│
│                     ↓                                                │
│  5. Module is ACTIVE and fully functional                           │
└─────────────────────────────────────────────────────────────────────┘
```

### What's Actually Happening (Failure Modes)

#### 1. **Tool Sprawl & Confusion**
20+ module-related tools with overlapping responsibilities:
- `start_module_design` vs `design_module_schema`
- `propose_module_schema` vs `refine_module_schema`
- `approve_module_design` vs `build_app_tool`
- `generate_model_code`, `generate_canvas_code`, `generate_tool_definition`

**Problem**: The AI doesn't know which tool to use when.

#### 2. **State Machine Gaps**
`ModuleDesignSession` has states but transitions aren't enforced:
```
designing → schema_proposed → approved → generating → testing → deployed
```

**Problem**: Tools don't check/update state properly, leaving sessions orphaned.

#### 3. **Code Generation Failures**
When `approve_module_design` runs:
- Dynamic table creation may fail silently
- Canvas ERB generation may produce invalid code
- Tool definitions may not register properly
- Agent plugins may not get created

**Problem**: No transactional safety - partial failures leave broken modules.

#### 4. **Missing End-to-End Testing**
No automated tests for the full flow:
```
design → approve → create table → canvases work → tools work → agent works
```

**Problem**: Regressions go unnoticed.

### Current Tool Inventory (Module Building)

| Tool | Purpose | Status |
|------|---------|--------|
| `start_module_design` | Create design session | Works |
| `propose_module_schema` | Propose schema to user | Works but verbose |
| `refine_module_schema` | Update proposed schema | Rarely used |
| `approve_module_design` | Build the module | **BROKEN** - partial failures |
| `design_module_schema` | Alternative schema tool | Redundant |
| `generate_model_code` | Gen Ruby model code | Works standalone |
| `generate_canvas_code` | Gen ERB canvas code | Works standalone |
| `generate_tool_definition` | Gen tool JSON | Works standalone |
| `register_module_canvas` | Register canvas | Works |
| `validate_module` | Validate module | Works |
| `diagnose_module` | Find issues | Works |
| `repair_module` | Fix issues | Works |
| `extend_module_schema` | Add fields | Untested |
| `update_module` | Update module | Works |

---

## 🔧 Platform Factory Redesign

### Principle 1: Simplify the Tool Surface

**Reduce from 14 tools to 5 core tools:**

| Tool | Purpose |
|------|---------|
| `design_module` | Start or continue designing a module (combines start + propose + refine) |
| `build_module` | Actually create the module (the big red button) |
| `update_module` | Add fields, canvases, fix issues (combines extend + repair) |
| `diagnose_module` | Find issues with a module |
| `delete_module` | Remove a module |

**The AI only needs to know:**
1. `design_module` - Talk about what to build
2. `build_module` - Actually build it
3. `update_module` - Fix or enhance it

### Principle 2: Transactional Module Creation

Wrap the entire creation in a database transaction:

```ruby
class ModuleBuildService
  def build!(design_session)
    AppModule.transaction do
      # 1. Create AppModule record
      app_module = create_app_module(design_session)
      
      # 2. Create dynamic table
      create_dynamic_table(app_module)
      
      # 3. Create canvases
      create_canvases(app_module)
      
      # 4. Create tools
      create_tools(app_module)
      
      # 5. Create agent
      create_agent(app_module)
      
      # 6. Create scheduled tasks
      create_scheduled_tasks(app_module)
      
      # 7. Create workflows
      create_workflows(app_module)
      
      # 8. Mark as deployed
      app_module.mark_deployed!
      design_session.complete!
      
      app_module
    end
  rescue => e
    # Full rollback - no partial state
    design_session.mark_failed!(e.message)
    raise
  end
end
```

### Principle 3: Canvas Generation Strategy

**Current Problem**: AI generates ERB code which often has bugs.

**Solution**: Template-based generation with data binding:

```ruby
class CanvasTemplateRenderer
  TEMPLATES = {
    list: 'module_list_template.html.erb',
    form: 'module_form_template.html.erb',
    detail: 'module_detail_template.html.erb',
    dashboard: 'module_dashboard_template.html.erb',
    kanban: 'module_kanban_template.html.erb',
    calendar: 'module_calendar_template.html.erb'
  }
  
  def render(canvas_type, app_module)
    template = load_template(TEMPLATES[canvas_type])
    template.render(
      module: app_module,
      fields: app_module.enhanced_fields,
      slug: app_module.slug,
      name: app_module.name
    )
  end
end
```

**Benefits**:
- Tested templates that work
- AI doesn't write ERB code
- Consistent UI across modules
- Easy to update all modules when template improves

### Principle 4: State Machine Enforcement

```ruby
class ModuleDesignSession
  include AASM
  
  aasm column: :status do
    state :active, initial: true
    state :schema_proposed
    state :approved
    state :building
    state :deployed
    state :failed
    state :cancelled
    
    event :propose_schema do
      transitions from: [:active, :schema_proposed], to: :schema_proposed
    end
    
    event :approve do
      transitions from: :schema_proposed, to: :approved
    end
    
    event :start_build do
      transitions from: :approved, to: :building
    end
    
    event :complete do
      transitions from: :building, to: :deployed
    end
    
    event :fail do
      transitions from: [:building, :approved], to: :failed
    end
  end
end
```

---

## 🌐 Website Progression: The Big Picture

### The Evolution

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           WEBSITE PROGRESSION                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   STAGE 1: LANDING PAGE                                                     │
│   ━━━━━━━━━━━━━━━━━━━━━                                                     │
│   • Single page                                                              │
│   • Static HTML + styling                                                   │
│   • Lead capture form                                                       │
│   • Analytics tracking                                                       │
│   • Model: LandingPage                                                      │
│                                                                              │
│           ↓                                                                  │
│                                                                              │
│   STAGE 2: WEBSITE                                                          │
│   ━━━━━━━━━━━━━━━━                                                          │
│   • Multiple pages                                                          │
│   • Navigation structure                                                     │
│   • Blog/content pages                                                      │
│   • Contact forms                                                           │
│   • Model: Website (has_many :pages)                                        │
│                                                                              │
│           ↓                                                                  │
│                                                                              │
│   STAGE 3: WEB APP                                                          │
│   ━━━━━━━━━━━━━━━                                                           │
│   • Website + dynamic functionality                                         │
│   • User authentication                                                      │
│   • Forms that create records                                               │
│   • Automation behind the scenes                                            │
│   • Like AppModules but public-facing                                       │
│   • Model: WebApp (has_many :pages, :modules, :automations)                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Current State: LandingPage Model

```ruby
# What we have today
class LandingPage < ApplicationRecord
  belongs_to :entity
  belongs_to :template, optional: true
  
  # Single HTML blob
  attribute :html_content, :text
  attribute :css_content, :text
  attribute :js_content, :text
  
  # Status
  attribute :status  # draft, published
  
  # Analytics
  attribute :views_count
  attribute :conversions_count
end
```

### Stage 2: Website Model (Proposed)

```ruby
class Website < ApplicationRecord
  belongs_to :entity
  belongs_to :template, optional: true
  
  has_many :website_pages, dependent: :destroy
  has_one :homepage, -> { where(is_homepage: true) }, class_name: 'WebsitePage'
  has_one :global_header, -> { where(is_header: true) }, class_name: 'WebsiteComponent'
  has_one :global_footer, -> { where(is_footer: true) }, class_name: 'WebsiteComponent'
  
  # Domain configuration
  attribute :subdomain, :string  # mysite.amos.io
  attribute :custom_domain, :string  # www.mysite.com
  
  # Global styles
  attribute :global_css, :text
  attribute :global_js, :text
  attribute :branding, :jsonb  # { logo, colors, fonts }
  
  # Navigation structure
  attribute :nav_structure, :jsonb  # [ { title, page_id, children: [] } ]
  
  # SEO
  attribute :default_meta, :jsonb  # { title_suffix, description }
end

class WebsitePage < ApplicationRecord
  belongs_to :website
  belongs_to :parent_page, class_name: 'WebsitePage', optional: true
  has_many :child_pages, class_name: 'WebsitePage', foreign_key: :parent_page_id
  
  attribute :slug, :string  # about-us
  attribute :title, :string
  attribute :html_content, :text
  attribute :page_type, :string  # content, blog_post, contact, gallery
  attribute :is_homepage, :boolean
  attribute :meta_tags, :jsonb
  attribute :status, :string  # draft, published
  
  # Page-specific forms
  has_many :page_forms
end
```

### Stage 3: WebApp Model (Proposed)

A WebApp is a Website + AppModules exposed to the public:

```ruby
class WebApp < ApplicationRecord
  belongs_to :entity
  belongs_to :website  # The public face
  
  has_many :web_app_modules, dependent: :destroy
  has_many :app_modules, through: :web_app_modules
  
  has_many :web_app_automations
  has_many :web_app_forms
  
  # Which modules are exposed publicly
  attribute :public_modules, :jsonb  # [{ module_id, permissions, form_only }]
  
  # Authentication
  attribute :requires_auth, :boolean
  attribute :auth_type, :string  # none, email_link, password, oauth
end

class WebAppForm < ApplicationRecord
  belongs_to :web_app
  belongs_to :app_module
  belongs_to :website_page
  
  # Form creates records in the module
  attribute :field_mappings, :jsonb  # { form_field => module_field }
  attribute :on_submit_workflow_id, :integer
  attribute :confirmation_message, :text
end
```

### The Flow: From Landing Page to Web App

```
USER JOURNEY:
━━━━━━━━━━━━━

1. "Build me a landing page for my coaching business"
   → LandingPage created with lead capture form
   → Form submissions go to Contacts

2. "I need more pages - about, services, testimonials"
   → Convert to Website (multi-page)
   → Add pages with shared header/footer/nav
   → Same domain, professional site

3. "I want clients to book sessions and see their history"
   → Add AppModule: "Client Sessions"
   → Create WebAppForm on /book-session page
   → Form creates record in Client Sessions module
   → Client can log in and see their sessions
   → Automations: Send confirmation, add to calendar, remind before

THE MAGIC:
━━━━━━━━━━
- User thinks they're building a website
- They're actually building an app
- No code, no deployment, no infrastructure
- AI handles everything

THAT'S THE FUTURE.
```

---

## 🛠 Implementation Plan

### Phase 1: Platform Factory Fixes (Week 1-2)

1. **Create `ModuleBuildService`** - Transactional module creation
2. **Simplify tools** - Consolidate to 5 core tools
3. **Template-based canvases** - Stop generating ERB
4. **Add state machine** - AASM for ModuleDesignSession
5. **End-to-end tests** - Full flow testing

### Phase 2: Website Foundation (Week 3-4)

1. **Create `Website` model** - Multi-page structure
2. **Create `WebsitePage` model** - Individual pages
3. **Landing Page migration** - Convert existing to new structure
4. **Website builder** - AI tool to create websites
5. **Navigation system** - Auto-generate nav from page structure

### Phase 3: WebApp Layer (Week 5-6)

1. **Create `WebApp` model** - Website + modules
2. **Create `WebAppForm` model** - Public forms
3. **Public module views** - Read-only/form-only exposure
4. **Authentication** - Simple email-link auth
5. **Form-to-module pipeline** - Submissions create records

### Phase 4: Polish & Integration (Week 7-8)

1. **Unified builder** - "Build me X" → right type auto-selected
2. **Template library** - Pre-built website templates
3. **Domain management** - Custom domains
4. **Analytics** - Unified analytics across pages
5. **SEO tools** - AI-powered SEO suggestions

---

## 💡 The Vision: Building the Future

### What We're Actually Building

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│   AMOS = The Operating System for Business                                  │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │                                                                       │  │
│   │   USER SAYS:                         AMOS DOES:                       │  │
│   │   ─────────                          ─────────                        │  │
│   │                                                                       │  │
│   │   "I need a CRM"                     → Builds CRM module             │  │
│   │                                       → Syncs with email             │  │
│   │                                       → Adds automation              │  │
│   │                                                                       │  │
│   │   "Make me a website"                → Creates multi-page site       │  │
│   │                                       → Adds contact forms           │  │
│   │                                       → Connects to CRM              │  │
│   │                                                                       │  │
│   │   "Let clients book sessions"        → Adds booking form to site    │  │
│   │                                       → Creates session records      │  │
│   │                                       → Sends confirmations          │  │
│   │                                       → Syncs to calendar            │  │
│   │                                                                       │  │
│   │   "Remind me about follow-ups"       → Scheduled task checks CRM    │  │
│   │                                       → DMs you about stale leads    │  │
│   │                                                                       │  │
│   └──────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│   THE USER NEVER:                                                           │
│   • Writes code                                                             │
│   • Configures servers                                                      │
│   • Manages databases                                                       │
│   • Sets up integrations manually                                           │
│   • Learns a complex UI                                                     │
│                                                                              │
│   THEY JUST TALK TO AMOS.                                                   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Why This Matters

1. **Democratization of Software** - Anyone can build apps
2. **Speed** - Minutes instead of months
3. **Integration-First** - Everything connects automatically
4. **AI-Native** - Not AI bolted on, AI is the interface
5. **Continuous Improvement** - Modules improve as AI learns

### The Competitive Moat

| Competitor | What They Do | Our Advantage |
|------------|--------------|---------------|
| Webflow | Visual website builder | We're conversational + integrated |
| Airtable | Spreadsheet-database | We have AI agents + automation |
| Zapier | Connect apps | We BUILD the apps that get connected |
| Bubble | No-code app builder | We're AI-first, not visual-first |
| GPT/Claude | Chat with AI | We have persistence, memory, tools, deployment |

**We're not competing with any one of these. We're replacing all of them.**

---

## 📋 Next Steps

1. [ ] Review this plan with stakeholders
2. [ ] Create detailed technical specs for each phase
3. [ ] Prioritize: Fix Platform Factory before adding Website
4. [ ] Set up end-to-end testing infrastructure
5. [ ] Begin Phase 1 implementation

---

*"The best interface is no interface. The best code is no code. The best infrastructure is invisible."*

*— AMOS Labs Philosophy*

