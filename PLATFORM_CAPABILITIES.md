# AMOS Platform Capabilities

> **Purpose**: This document describes what the AMOS platform can do. It serves as the single source of truth for agents, developers, and customers.

---

## 🧠 What is AMOS?

AMOS (AI Marketing Operating System) is an **AI-powered business operating system** that combines:

- **AI Agents** that understand your business and execute tasks
- **Custom Apps/Modules** that you design through conversation
- **Automations** that run in the background
- **Integrations** that connect your existing tools
- **Collaboration Hub** for team communication

**The key difference**: Unlike traditional software where features are fixed, AMOS learns and adapts. Every app you create becomes immediately accessible to your AI team.

---

## 🤖 AI Agents

### How Agents Work

Agents are specialized AI assistants with different expertise. When you chat with Amos (the orchestrator), it routes your request to the right specialist.

### Core Agents

| Agent | Specialty | Can Do |
|-------|-----------|--------|
| **Amos** | Orchestrator | Routes requests, coordinates agents, remembers context |
| **Platform Factory** | App Builder | Designs and builds custom apps through conversation |
| **Web Research Specialist** | Research | Searches the web, analyzes pages, compiles findings |
| **Document Export Agent** | Documents | Creates PDFs, CSVs, Excel files from any data |
| **Data Analyst** | Analytics | Analyzes data, creates visualizations, finds patterns |
| **Email Specialist** | Communication | Drafts emails, manages sequences, handles outreach |
| **Social Media Manager** | Social | Creates posts, schedules content, tracks engagement |
| **Module Architect** | Maintenance | Fixes, updates, and enhances existing modules |

### Agent Collaboration

Agents can ask each other for help. For example:
- Document Export Agent needs data → asks Web Research Specialist
- Platform Factory needs to validate data → asks Data Analyst
- Any agent can save data to the **Scratchpad** for another agent to pick up

### What Agents Know

- Your entity's modules, data, and configuration
- Connected integrations and their capabilities
- Your team members and their roles
- Recent activity and context from conversations

---

## 📱 Custom Apps/Modules

### What You Can Build

Through conversation with Platform Factory, you can create apps that include:

- **Data Storage** - Custom fields and records
- **Views** - Lists, forms, dashboards, kanban boards, calendars
- **Automations** - Scheduled tasks, status workflows, webhooks
- **Agent Integration** - Your AI team can immediately use any app you create

### Field Types & UI Components

| Field Type | UI Component | Use For |
|------------|--------------|---------|
| `string` | Text input | Names, titles, short text |
| `text` | Textarea | Descriptions, notes |
| `text` + `rich_text_editor` | WYSIWYG Editor | Articles, rich content |
| `select` | Dropdown | Status, category, type |
| `multi_select` | Checkbox group | Tags, multiple selections |
| `boolean` | Checkbox | Yes/no flags |
| `integer` | Number input | Counts, quantities |
| `decimal` | Number input | Prices, percentages |
| `date` | Date picker | Due dates, birthdays |
| `datetime` | DateTime picker | Appointments, events |
| `reference` | Linked dropdown | Foreign keys to other data |
| `json` | Code editor | Complex nested data |

### Advanced UI Components

| Component | Description | Use For |
|-----------|-------------|---------|
| `rich_text_editor` | Full WYSIWYG with formatting | Articles, documentation |
| `code_editor` | Syntax-highlighted editor | JSON, HTML, custom code |
| `color_picker` | Visual color selection | Theming, branding |
| `image_upload` | File upload with preview | Avatars, logos |
| `file_upload` | File attachment | Documents, PDFs |
| `rating` | Star rating (1-5) | Reviews, scores |
| `slider` | Numeric slider | Progress, percentages |
| `tags` | Tag input with autocomplete | Keywords, labels |
| `user_select` | User dropdown | Assignment, ownership |
| `money` | Currency input | Prices, budgets |
| `address` | Structured address fields | Locations, shipping |

### Canvas Types (Views)

| Type | Description | Best For |
|------|-------------|----------|
| `data_grid` | Sortable/filterable table | Lists of records |
| `form` | Record creation/editing | Adding new data |
| `detail` | Single record view | Viewing full record |
| `dashboard` | Charts, KPIs, metrics | Summaries and analytics |
| `kanban` | Drag-drop columns | Status workflows |
| `calendar` | Date-based view | Events, schedules |
| `gallery` | Visual grid | Media-heavy content |
| `freeform` | Custom HTML/CSS/JS | Anything creative |

### The Ecosystem Effect

When you create an app, it's not isolated. It becomes part of your ecosystem:

✅ **Amos can query it**: "How many open tickets do we have?"  
✅ **Other apps can reference it**: Link customers to orders  
✅ **Workflows can trigger from it**: Notify team on status change  
✅ **Reports can include it**: Pull data into dashboards  
✅ **Agents can act on it**: Auto-categorize, suggest actions

---

## ⚡ Automations

### Scheduled Tasks

Run agent tasks on a schedule:
- Daily reports at 9am
- Weekly summaries every Monday
- Hourly data syncs
- Custom cron expressions

### Workflows

Trigger actions based on events:
- Status changed → Notify team
- Record created → Send welcome email
- Due date approaching → Create reminder
- Approval needed → Route to manager

### Webhooks

Receive events from external systems:
- Stripe payment received → Update customer
- Zendesk ticket created → Log in CRM
- GitHub push → Trigger deployment
- Any HTTP POST → Execute agent task

---

## 🔗 Integrations

### Available Integrations

| Integration | Type | Capabilities |
|-------------|------|--------------|
| **HubSpot** | CRM | Sync contacts, companies, deals |
| **Stripe** | Payments | Customers, subscriptions, invoices |
| **SendGrid** | Email | Send emails, manage templates |
| **Slack** | Communication | Post messages, receive commands |
| **Google** | Suite | Calendar, Drive, Sheets |
| **Zapier** | Automation | Connect 5000+ apps |

### How Agents Use Integrations

When you connect an integration, agents gain new abilities:
- "Sync my HubSpot contacts" → Pulls data automatically
- "Create a Stripe invoice" → Generates and sends invoice
- "Post to Slack when deal closes" → Sets up automation

---

## 👥 Collaboration Hub

### Team Communication

- **Work Streams** - Topic-based channels for projects
- **Direct Messages** - Private conversations
- **Agent Threads** - Collaborate with AI on tasks
- **Activity Feeds** - See what's happening across apps

### Handoffs & Approvals

- Agents can ask for human approval before proceeding
- Route decisions to specific team members
- Track approval history and audit trail

### Notifications

- In-app notifications for mentions and updates
- Email digests for offline activity
- Push notifications (coming soon)

---

## 📊 Data & Analytics

### What's Tracked

- All record changes with timestamps
- Agent activity and tool usage
- User sessions and interactions
- Integration sync history

### Reporting

- Ask Amos: "Show me a report on X"
- Create saved visualizations
- Export to PDF, CSV, Excel
- Schedule automated reports

### The Freeform Canvas

Agents can create any visualization using full HTML/CSS/JS:
- Custom dashboards
- Interactive charts
- Infographics
- Data explorations
- Creative presentations

---

## 🚀 Getting Started

1. **Chat with Amos** - Just describe what you need
2. **Build an App** - Say "I need a [knowledge base / inventory tracker / etc.]"
3. **Connect Integrations** - Link your existing tools
4. **Set Up Automations** - Describe what should happen automatically
5. **Invite Your Team** - Add users with appropriate roles

---

## 🛠️ For Agents: Quick Reference

### Discovering Capabilities

```ruby
# Get platform documentation
get_platform_capabilities(topic: 'all')

# Get customer context (existing modules, integrations, etc.)
get_platform_capabilities(topic: 'customer_context')

# Get UI components available
get_platform_capabilities(topic: 'ui_components')
```

### Creating Visualizations

Use `create_freeform_canvas` for ALL visualizations. You have full HTML/CSS/JS freedom.

```ruby
create_freeform_canvas(
  title: "My Dashboard",
  html: "<div class='dashboard'>...</div>",
  css: ".dashboard { ... }",
  javascript: "// Your code here",
  libraries: ["chart.js"],  # Optional CDN libraries
  data: { ... }  # Available as window.canvasData
)
```

### Building Modules

1. `get_platform_capabilities(topic: 'customer_context')` - Understand their setup
2. `ask_user` with `canvas_content` - Show design preview
3. `propose_module_schema` - Register the design
4. `approve_module_design` - Build when user approves

### After Building

Always communicate the ecosystem value:

> "Your [App Name] is live! Here's what you can do now:
> - Ask me questions about your data
> - Connect it to your workflows
> - Your other agents can access it too
> - Set up automations to run automatically"

---

*Last updated: January 2026*

