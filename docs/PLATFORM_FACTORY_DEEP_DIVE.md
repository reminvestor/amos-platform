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

## 🧠 The Full Ecosystem Integration (The Real Magic)

**This is the key differentiator.** We're not just building websites or apps. We're building **fully integrated ecosystem citizens** that come alive the moment they're created.

### What Gets Created When You "Build" Something

```
USER: "Build me a knowledge base for my product documentation"

                    ↓ COLLABORATIVE PLANNING ↓

┌─────────────────────────────────────────────────────────────────────────────┐
│                        AMOS PLANS THE FULL SOLUTION                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  📋 THE PLAN (shown to user for approval):                                  │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ KNOWLEDGE BASE APPLICATION                                             │ │
│  │ ━━━━━━━━━━━━━━━━━━━━━━━━━━                                             │ │
│  │                                                                         │ │
│  │ 📊 DATA MODEL                                                          │ │
│  │ • Articles (title, content, category, status, author, views)           │ │
│  │ • Categories (name, parent_category, icon)                             │ │
│  │ • Article Feedback (article_id, helpful, comment)                      │ │
│  │                                                                         │ │
│  │ 🌐 WEBSITE (Public-Facing)                                             │ │
│  │ • Homepage with search and categories                                  │ │
│  │ • Article pages with rich formatting                                   │ │
│  │ • Category browsing                                                    │ │
│  │ • Search results page                                                  │ │
│  │ • "Was this helpful?" feedback widget                                  │ │
│  │                                                                         │ │
│  │ 📦 MODULE (Backend Management)                                          │ │
│  │ • Article editor with WYSIWYG                                          │ │
│  │ • Category management                                                  │ │
│  │ • Article analytics dashboard                                          │ │
│  │ • Feedback review queue                                                │ │
│  │                                                                         │ │
│  │ 🤖 KNOWLEDGE BASE AGENT                                                │ │
│  │ • Answers questions from knowledge base content                        │ │
│  │ • Helps write and improve articles                                     │ │
│  │ • Identifies content gaps from search queries                          │ │
│  │ • Monitors article performance                                         │ │
│  │                                                                         │ │
│  │ 🔧 CUSTOM TOOLS                                                        │ │
│  │ • create_article, update_article, publish_article                      │ │
│  │ • search_knowledge_base (semantic search)                              │ │
│  │ • get_article_analytics                                                │ │
│  │ • suggest_related_articles                                             │ │
│  │                                                                         │ │
│  │ 🔌 INTEGRATIONS                                                        │ │
│  │ • Intercom (sync articles to help center)                              │ │
│  │ • Zendesk (import support tickets as article ideas)                    │ │
│  │ • Slack (notify team of new articles)                                  │ │
│  │ • Google Analytics (track article views)                               │ │
│  │                                                                         │ │
│  │ ⚡ WORKFLOWS                                                           │ │
│  │ • Draft → Review → Published (with approval)                           │ │
│  │ • Low article views → Suggest improvement                              │ │
│  │ • Negative feedback → Create support ticket                            │ │
│  │                                                                         │ │
│  │ 📅 SCHEDULED TASKS                                                     │ │
│  │ • Daily: Sync analytics from GA                                        │ │
│  │ • Weekly: Content gap analysis report                                  │ │
│  │ • Monthly: Stale content detection (>90 days no update)                │ │
│  │                                                                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  USER: "Looks perfect, build it!"                                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

                    ↓ EXECUTION ↓

┌─────────────────────────────────────────────────────────────────────────────┐
│                        ALL OF THIS GETS CREATED                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ✅ AppModule records (Articles, Categories, ArticleFeedback)               │
│  ✅ Database tables with proper schema                                       │
│  ✅ ModuleCanvas records (list, form, dashboard, etc.)                       │
│  ✅ Website with WebsitePage records                                         │
│  ✅ WebApp linking website to modules                                        │
│  ✅ AgentPlugin: "Knowledge Base Expert"                                     │
│  ✅ ToolDefinition records (CRUD + custom tools)                             │
│  ✅ ModuleIntegration links (Intercom, Zendesk, Slack, GA)                   │
│  ✅ Workflow records                                                          │
│  ✅ ScheduledAgentTask records                                                │
│  ✅ RagStore with knowledge base content for semantic search                 │
│                                                                              │
│  THE SYSTEM IS ALIVE AND READY TO USE IMMEDIATELY                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### The Ecosystem Effect

When you create an app, it doesn't exist in isolation. It becomes a **citizen of the AMOS ecosystem**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ECOSYSTEM CITIZENSHIP                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   YOUR NEW KNOWLEDGE BASE:                                                  │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  🤖 AMOS (Orchestrator)                                             │   │
│   │     ↕                                                               │   │
│   │  "What articles do we have about billing?"                          │   │
│   │     → Routes to Knowledge Base Agent                                │   │
│   │     → Agent uses search_knowledge_base tool                        │   │
│   │     → Returns results + offers to show in canvas                    │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  🔗 OTHER AGENTS CAN USE IT                                         │   │
│   │                                                                      │   │
│   │  Support Agent: "Let me search the knowledge base for an answer"    │   │
│   │  Sales Agent: "I'll include a link to our pricing FAQ"              │   │
│   │  Marketing Agent: "The knowledge base shows these topics trending"  │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  ⚡ WORKFLOWS TRIGGER AUTOMATICALLY                                 │   │
│   │                                                                      │   │
│   │  Article published → Syncs to Intercom → Notifies Slack            │   │
│   │  Low views detected → Agent suggests improvements                   │   │
│   │  Stale content → Review task created                               │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  📊 UNIFIED ANALYTICS                                               │   │
│   │                                                                      │   │
│   │  All modules feed into unified dashboards                           │   │
│   │  Cross-module insights (KB views vs support tickets)                │   │
│   │  AI-powered trend detection                                         │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📋 The Collaborative Planning Process

**This is crucial.** Before building anything complex, there must be a planning phase where:
1. User describes what they want
2. Planner Agent creates a comprehensive plan
3. User reviews and refines the plan
4. User approves → Building starts

### The Planner Agent

```ruby
# New agent: The Planner
AgentPlugin.create!(
  name: 'Application Planner',
  slug: 'app_planner',
  role: 'architect',
  description: 'Creates comprehensive application plans before building. ' \
               'Understands the full AMOS ecosystem and designs integrated solutions.',
  system_prompt: PLANNER_PROMPT
)
```

### The Planning Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          PLANNING FLOW                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PHASE 1: DISCOVERY                                                         │
│  ━━━━━━━━━━━━━━━━━━                                                         │
│                                                                              │
│  User: "I need a knowledge base for product docs"                           │
│                                                                              │
│  Planner asks:                                                              │
│  • Who will use it? (customers, internal team, both?)                       │
│  • How many articles do you expect?                                         │
│  • Do you have existing docs to import?                                     │
│  • What integrations do you need? (help desk, chat, etc.)                   │
│  • Who can publish vs who can view?                                         │
│                                                                              │
│  ───────────────────────────────────────────────────────────────────────    │
│                                                                              │
│  PHASE 2: PLAN CREATION                                                     │
│  ━━━━━━━━━━━━━━━━━━━━━                                                      │
│                                                                              │
│  Planner creates ApplicationPlan record:                                    │
│  {                                                                          │
│    name: "Product Knowledge Base",                                          │
│    description: "Customer-facing docs with internal management",            │
│    components: {                                                            │
│      modules: [...],                                                        │
│      website: {...},                                                        │
│      agent: {...},                                                          │
│      tools: [...],                                                          │
│      integrations: [...],                                                   │
│      workflows: [...],                                                      │
│      scheduled_tasks: [...]                                                 │
│    },                                                                       │
│    estimated_build_time: "2-3 minutes",                                     │
│    status: "pending_approval"                                               │
│  }                                                                          │
│                                                                              │
│  Shows plan preview in canvas                                               │
│                                                                              │
│  ───────────────────────────────────────────────────────────────────────    │
│                                                                              │
│  PHASE 3: REFINEMENT                                                        │
│  ━━━━━━━━━━━━━━━━━━━                                                        │
│                                                                              │
│  User: "Actually, I also need video embedding support"                      │
│  Planner: Updates plan, adds video fields, suggests Vimeo/YouTube embed     │
│                                                                              │
│  User: "And I want articles to auto-translate to Spanish"                   │
│  Planner: Adds translation workflow, suggests DeepL integration             │
│                                                                              │
│  ───────────────────────────────────────────────────────────────────────    │
│                                                                              │
│  PHASE 4: APPROVAL                                                          │
│  ━━━━━━━━━━━━━━━━━                                                          │
│                                                                              │
│  User: "Perfect, build it!"                                                 │
│                                                                              │
│  Plan status → "approved"                                                   │
│  Triggers: ApplicationBuildService.execute!(plan)                           │
│                                                                              │
│  ───────────────────────────────────────────────────────────────────────    │
│                                                                              │
│  PHASE 5: EXECUTION (with progress updates)                                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━                                │
│                                                                              │
│  ✅ Creating Articles module... done                                         │
│  ✅ Creating Categories module... done                                       │
│  ✅ Creating database tables... done                                         │
│  ✅ Setting up Knowledge Base Expert agent... done                           │
│  ✅ Registering 6 custom tools... done                                       │
│  ✅ Creating website pages... done                                           │
│  ✅ Configuring Intercom integration... done                                 │
│  ✅ Setting up workflows... done                                             │
│  ✅ Scheduling background tasks... done                                      │
│                                                                              │
│  🎉 Your Knowledge Base is live!                                            │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### The ApplicationPlan Model

```ruby
class ApplicationPlan < ApplicationRecord
  belongs_to :entity
  belongs_to :created_by, class_name: 'User'
  
  # Status: drafting → pending_approval → approved → building → completed → failed
  attribute :status, :string, default: 'drafting'
  
  # The full plan specification
  attribute :plan_spec, :jsonb, default: {}
  # {
  #   name: "Knowledge Base",
  #   description: "...",
  #   modules: [
  #     { name: "Articles", fields: [...], views: [...] },
  #     { name: "Categories", fields: [...] }
  #   ],
  #   website: {
  #     pages: [...],
  #     theme: "documentation",
  #     features: ["search", "categories", "feedback"]
  #   },
  #   agent: {
  #     name: "Knowledge Base Expert",
  #     capabilities: [...],
  #     personality: "helpful, technical"
  #   },
  #   tools: [...],
  #   integrations: ["intercom", "zendesk"],
  #   workflows: [...],
  #   scheduled_tasks: [...]
  # }
  
  # User feedback during refinement
  attribute :refinement_history, :jsonb, default: []
  
  # Build results
  has_many :app_modules
  has_one :website
  has_one :web_app
  has_one :agent_plugin
  
  # Timestamps
  attribute :approved_at, :datetime
  attribute :build_started_at, :datetime
  attribute :completed_at, :datetime
end
```

### Why This Matters

1. **User Control** - User sees exactly what will be built before it happens
2. **Quality** - Planner can think holistically, not just react to commands
3. **Complexity Handling** - Multi-component apps need planning
4. **Trust** - User approves the plan, so they own the outcome
5. **Refinement** - Can iterate on the plan before expensive building

---

## 🛠 Implementation Plan

### Phase 1: Foundation & Planning System (Week 1-2)

1. **Create `ApplicationPlan` model** - The plan record with full spec
2. **Create `ApplicationPlannerService`** - Builds comprehensive plans
3. **Create `ApplicationBuildService`** - Transactional execution of plans
4. **Simplify tools** - Consolidate to `plan_application`, `build_application`, `update_application`
5. **Planning canvas** - Visual plan preview for user approval

### Phase 2: Ecosystem Components (Week 3-4)

1. **App Agent Generation** - Every app gets a dedicated expert agent
2. **Tool Auto-Registration** - CRUD + custom tools registered automatically
3. **Integration Wiring** - ModuleIntegration records linked to available integrations
4. **Workflow Templates** - Pre-built workflow patterns per archetype
5. **Scheduled Task Setup** - Background tasks created and scheduled

### Phase 3: Website & WebApp Layer (Week 5-6)

1. **Create `Website` model** - Multi-page structure with shared components
2. **Create `WebsitePage` model** - Individual pages with templates
3. **Create `WebApp` model** - Website + modules combined
4. **Public Module Exposure** - Forms that create records
5. **Simple Authentication** - Email-link auth for public users

### Phase 4: Integration & Polish (Week 7-8)

1. **End-to-end tests** - Full flow testing from plan → deploy
2. **Template library** - Pre-built application templates (KB, CRM, etc.)
3. **Migration** - Convert existing LandingPages to new system
4. **Analytics** - Unified analytics across all components
5. **Documentation** - Update PLATFORM_CAPABILITIES.md

---

## 💡 The Vision: Building the Future

### What We're Actually Building

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│   AMOS = The Operating System for Business                                  │
│                                                                              │
│   Every application you build becomes a FULL ECOSYSTEM CITIZEN:             │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │                                                                       │  │
│   │   "Build me a knowledge base"                                        │  │
│   │                                                                       │  │
│   │   ┌─────────────────────────────────────────────────────────────────┐│  │
│   │   │ 🌐 PUBLIC WEBSITE                                               ││  │
│   │   │    • Search, browse, read articles                              ││  │
│   │   │    • "Was this helpful?" feedback                               ││  │
│   │   │    • SEO optimized, mobile responsive                           ││  │
│   │   └─────────────────────────────────────────────────────────────────┘│  │
│   │              ↕ (connected)                                           │  │
│   │   ┌─────────────────────────────────────────────────────────────────┐│  │
│   │   │ 📦 BACKEND MODULE                                               ││  │
│   │   │    • Article editor, category management                        ││  │
│   │   │    • Analytics dashboard, feedback queue                        ││  │
│   │   │    • Version history, approval workflows                        ││  │
│   │   └─────────────────────────────────────────────────────────────────┘│  │
│   │              ↕ (powered by)                                          │  │
│   │   ┌─────────────────────────────────────────────────────────────────┐│  │
│   │   │ 🤖 KNOWLEDGE BASE EXPERT (AI Agent)                             ││  │
│   │   │    • Answers questions from content                             ││  │
│   │   │    • Helps write articles                                       ││  │
│   │   │    • Identifies content gaps                                    ││  │
│   │   │    • Other agents can ask it for help!                          ││  │
│   │   └─────────────────────────────────────────────────────────────────┘│  │
│   │              ↕ (uses)                                                │  │
│   │   ┌─────────────────────────────────────────────────────────────────┐│  │
│   │   │ 🔧 CUSTOM TOOLS                                                 ││  │
│   │   │    • create_article, search_knowledge_base                      ││  │
│   │   │    • get_article_analytics, suggest_improvements                ││  │
│   │   │    • Any agent in the system can use these!                     ││  │
│   │   └─────────────────────────────────────────────────────────────────┘│  │
│   │              ↕ (connected to)                                        │  │
│   │   ┌─────────────────────────────────────────────────────────────────┐│  │
│   │   │ 🔌 INTEGRATIONS                                                 ││  │
│   │   │    • Intercom: Sync articles to help center                     ││  │
│   │   │    • Zendesk: Import ticket themes as article ideas             ││  │
│   │   │    • Slack: Notify team of new publications                     ││  │
│   │   └─────────────────────────────────────────────────────────────────┘│  │
│   │              ↕ (automated by)                                        │  │
│   │   ┌─────────────────────────────────────────────────────────────────┐│  │
│   │   │ ⚡ WORKFLOWS & SCHEDULED TASKS                                  ││  │
│   │   │    • Draft → Review → Publish (with approval)                   ││  │
│   │   │    • Daily: Sync analytics, check for stale content             ││  │
│   │   │    • Weekly: Content gap report                                 ││  │
│   │   └─────────────────────────────────────────────────────────────────┘│  │
│   │                                                                       │  │
│   └──────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│   ALL OF THIS FROM ONE CONVERSATION.                                        │
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

## ✅ Implementation Status (January 17, 2026)

### Phase 1: Foundation & Planning System - COMPLETE ✅

| Component | Status | Files |
|-----------|--------|-------|
| ApplicationPlan model | ✅ | `app/models/application_plan.rb` |
| ApplicationPlannerService | ✅ | `app/services/application_planner_service.rb` |
| ApplicationBuildService | ✅ | `app/services/application_build_service.rb` |
| plan_application tool | ✅ | `app/services/tools/plan_application_tool.rb` |
| build_application tool | ✅ | `app/services/tools/build_application_tool.rb` |
| Planning canvas | ✅ | `app/views/scout/canvas/_application_plan_preview.html.erb` |
| Application Planner agent | ✅ | `db/seeds/application_planner.rb` |
| Migration | ✅ | `db/migrate/20260117200000_create_application_plans.rb` |

### Phase 2: Website Progression - COMPLETE ✅

| Component | Status | Files |
|-----------|--------|-------|
| Website model | ✅ | `app/models/website.rb` |
| WebsitePage model | ✅ | `app/models/website_page.rb` |
| WebApp model | ✅ | `app/models/web_app.rb` |
| WebAppModule model | ✅ | `app/models/web_app_module.rb` |
| WebsiteBuilderService | ✅ | `app/services/website_builder_service.rb` |
| Migration | ✅ | `db/migrate/20260117200001_create_websites.rb` |

### Phase 3: Enhanced Tools - COMPLETE ✅

| Component | Status | Files |
|-----------|--------|-------|
| get_platform_capabilities | ✅ | `app/services/tools/get_platform_capabilities_tool.rb` |
| update_application_plan | ✅ | `app/services/tools/update_application_plan_tool.rb` |
| Amos delegation update | ✅ | `app/services/amos_identity.rb` |

### Phase 4: Testing & Integration - COMPLETE ✅

| Component | Status | Files |
|-----------|--------|-------|
| Integration tests | ✅ | `test/services/application_planning_test.rb` |

---

## 🚀 How to Use

### Run Migrations
```bash
bin/rails db:migrate
```

### Seed Application Planner Agent
```bash
bin/rails db:seed
```

### Test the Flow

Tell Amos:
> "Build me a knowledge base for our product documentation"

The Application Planner will:
1. Ask clarifying questions about integrations, workflows, etc.
2. Create a comprehensive plan
3. Show a visual preview in the canvas
4. Wait for approval
5. Build everything transactionally

---

## 📊 Architecture Summary

```
USER REQUEST
      ↓
┌─────────────────────────────────────────────────────────────────┐
│  AMOS (Orchestrator)                                            │
│  Detects "build me a..." → Delegates to Application Planner    │
└─────────────────────────────────────────────────────────────────┘
      ↓
┌─────────────────────────────────────────────────────────────────┐
│  APPLICATION PLANNER (Agent)                                     │
│  Uses: plan_application, update_application_plan, ask_user      │
│  Creates: ApplicationPlan with full spec                         │
└─────────────────────────────────────────────────────────────────┘
      ↓ (user approves)
┌─────────────────────────────────────────────────────────────────┐
│  build_application Tool                                          │
│  Calls: ApplicationBuildService.execute!                         │
└─────────────────────────────────────────────────────────────────┘
      ↓
┌─────────────────────────────────────────────────────────────────┐
│  ApplicationBuildService (Transactional)                         │
│                                                                  │
│  Phase 1: build_modules!                                         │
│  Phase 2: build_agent!                                           │
│  Phase 3: build_tools!                                           │
│  Phase 4: wire_integrations!                                     │
│  Phase 5: build_workflows!                                       │
│  Phase 6: build_scheduled_tasks!                                 │
│  Phase 7: build_webhooks!                                        │
│  Phase 8: build_website! → WebsiteBuilderService                │
│  Phase 9: finalize_build!                                        │
│                                                                  │
│  All in one transaction. Rollback on any failure.               │
└─────────────────────────────────────────────────────────────────┘
      ↓
┌─────────────────────────────────────────────────────────────────┐
│  RESULT: Full Ecosystem Citizen                                  │
│                                                                  │
│  ✅ AppModule(s) with database tables                            │
│  ✅ AI Agent that knows the domain                               │
│  ✅ CRUD + custom tools registered                               │
│  ✅ Integrations wired                                            │
│  ✅ Workflows active                                              │
│  ✅ Scheduled tasks running                                       │
│  ✅ Website (if requested)                                        │
│  ✅ WebApp with auth (if requested)                               │
└─────────────────────────────────────────────────────────────────┘
```

---

*"The best interface is no interface. The best code is no code. The best infrastructure is invisible."*

*— AMOS Labs Philosophy*

