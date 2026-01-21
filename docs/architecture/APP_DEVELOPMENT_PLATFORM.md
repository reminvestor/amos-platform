# App Development Platform Architecture

## Executive Summary

The App Development Platform transforms our module system into a full-featured **low-code/no-code application builder** that leverages our existing agent and tool infrastructure. Users can create sophisticated business applications through conversation with specialized AI agents, with the platform handling all technical complexity.

**Key Differentiators from competitors:**
- **Conversational Discovery**: Agents understand business intent, not just field requirements
- **Agent-Powered Apps**: Each app gets its own AI assistant for ongoing help
- **Workflow Integration**: Automations and agents work seamlessly within apps
- **Instant Preview**: See changes immediately, iterate in real-time
- **Platform Integration**: Leverage existing integrations, agents, and tools

---

## Core Concepts

### Hierarchy

```
Platform
├── Apps (complete business solutions)
│   ├── Modules (data entities within an app)
│   │   ├── Canvases (UI views)
│   │   ├── Actions (buttons, operations)
│   │   └── Tools (AI-callable operations)
│   ├── Workflows (automations)
│   ├── App Assistant (dedicated AI agent)
│   └── Integrations (external connections)
```

### Example: Social Media Manager App

```yaml
app: Social Media Manager
  description: "Plan, create, schedule, and analyze social media content"
  
  modules:
    - Posts (core content management)
    - Media Library (images, videos, templates)
    - Content Calendar (visual scheduling)
    - Analytics Dashboard (performance tracking)
    - Campaigns (grouped posts for initiatives)
  
  workflows:
    - Post Approval Flow (draft → review → approved → scheduled)
    - Auto-Publish (scheduled → publish to platforms)
    - Performance Sync (pull metrics from platforms)
    - Content Suggestions (AI-generated post ideas)
  
  app_assistant:
    name: "Social Media Strategist"
    capabilities:
      - Write engaging posts for any platform
      - Suggest optimal posting times
      - Analyze performance and recommend improvements
      - Generate content calendars
      - Create visual assets with AI
  
  integrations:
    - LinkedIn (publish, analytics)
    - Facebook (publish, analytics)
    - Twitter/X (publish, analytics)
    - Instagram (publish via Meta)
    - Buffer/Hootsuite (optional)
```

---

## Development Lifecycle

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        APP DEVELOPMENT LIFECYCLE                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    │
│  │DISCOVER │───▶│ DESIGN  │───▶│  BUILD  │───▶│  TEST   │───▶│ EVOLVE  │    │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘    │
│                                                                               │
│  App Architect   App Architect   Module Builder   User + Amos   User + Amos  │
│  Agent           Agent           Agent            App Assistant  App Assistant│
│                                                                               │
│  • User intent   • Blueprint     • Tables         • Preview      • Add fields │
│  • User stories  • Data models   • Models         • Iterate      • New views  │
│  • Workflows     • UI designs    • Canvases       • Refine       • Workflows  │
│  • Personas      • Actions       • Tools          • Deploy       • Integrations│
│                  • Integrations  • Workflows                                  │
│                  • Assistant     • Assistant                                  │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Discovery

### Conversation Flow

The **App Architect Agent** conducts a discovery conversation:

```
User: "I need a social media calendar"

App Architect: "Great! Let me help you design this. First, some questions:

**About Your Workflow:**
1. Is this just for you, or does a team use it?
2. Do posts need approval before publishing?
3. Do you want to actually publish to platforms, or just plan?

**About Content:**
4. What platforms? (Instagram, LinkedIn, Facebook, X, etc.)
5. Do you create content here or import from elsewhere?
6. Do you need AI help writing posts?

**About Analytics:**
7. Do you want to track performance (likes, shares, etc.)?
8. Do you need reporting or just visibility?

Take your time - the more I understand, the better I can design this for you!"
```

### Discovery Output: Intent Document

```yaml
app_intent:
  name: "Social Media Manager"
  primary_goal: "Plan, create, and schedule social media content with team approval"
  
  users:
    - role: "Content Creator"
      actions: ["create posts", "upload media", "submit for approval"]
    - role: "Approver"
      actions: ["review posts", "approve/reject", "request changes"]
    - role: "Publisher"
      actions: ["schedule approved posts", "monitor performance"]
  
  core_workflows:
    - name: "Content Creation"
      steps: ["draft", "add media", "submit for review"]
    - name: "Approval"
      steps: ["review", "approve/reject/request changes", "notify creator"]
    - name: "Publishing"
      steps: ["schedule", "auto-publish", "confirm live"]
    - name: "Analysis"
      steps: ["pull metrics", "generate insights", "suggest improvements"]
  
  integrations_needed:
    - "LinkedIn" (publish + analytics)
    - "Facebook" (publish + analytics)
  
  ai_assistance:
    - "Help write engaging posts"
    - "Suggest best posting times"
    - "Analyze what's working"
```

---

## Phase 2: Design

### Blueprint Generation

The App Architect generates a **Blueprint** from the intent:

```yaml
blueprint:
  app:
    name: "Social Media Manager"
    slug: "social_media_manager"
    icon: "share-2"
    color: "#1DA1F2"
  
  modules:
    - name: "Posts"
      slug: "posts"
      description: "Social media posts and content"
      is_primary: true
      
      fields:
        # === Content Section ===
        - name: "title"
          type: "string"
          label: "Post Title"
          required: true
          section: "content"
          help: "Internal reference name"
          
        - name: "content"
          type: "text"
          label: "Post Content"
          required: true
          section: "content"
          ui_component: "rich_text_editor"
          ai_assist: true  # Show "AI Write" button
          
        - name: "platforms"
          type: "multi_select"
          label: "Platforms"
          required: true
          section: "content"
          options: ["Instagram", "LinkedIn", "Facebook", "X"]
          
        - name: "media"
          type: "media_gallery"
          label: "Images/Videos"
          section: "content"
          accept: ["image/*", "video/*"]
          max_files: 10
          
        # === Scheduling Section ===
        - name: "scheduled_for"
          type: "datetime"
          label: "Schedule For"
          section: "scheduling"
          show_when:
            field: "status"
            in: ["approved", "scheduled"]
            
        - name: "auto_publish"
          type: "boolean"
          label: "Auto-publish when scheduled"
          section: "scheduling"
          default: true
          
        # === Workflow Section ===
        - name: "status"
          type: "select"
          label: "Status"
          section: "workflow"
          options:
            - value: "draft"
              label: "Draft"
              color: "gray"
            - value: "pending_review"
              label: "Pending Review"
              color: "yellow"
            - value: "approved"
              label: "Approved"
              color: "green"
            - value: "rejected"
              label: "Rejected"
              color: "red"
            - value: "scheduled"
              label: "Scheduled"
              color: "blue"
            - value: "published"
              label: "Published"
              color: "purple"
          default: "draft"
          
        - name: "reviewer_notes"
          type: "text"
          label: "Reviewer Notes"
          section: "workflow"
          visibility: "edit_only"
          show_when:
            field: "status"
            in: ["rejected", "pending_review"]
            
        # === Metrics Section (System-managed) ===
        - name: "impressions"
          type: "integer"
          section: "metrics"
          visibility: "read_only"
          default: 0
          
        - name: "engagement"
          type: "integer"
          section: "metrics"
          visibility: "read_only"
          default: 0
      
      canvases:
        - type: "list"
          name: "All Posts"
          is_default: true
          columns: ["title", "platforms", "status", "scheduled_for"]
          filters: ["status", "platforms"]
          sorting: ["scheduled_for", "created_at"]
          
        - type: "form"
          name: "Post Editor"
          layout: "tabbed"
          tabs:
            - name: "Content"
              icon: "edit-3"
              sections: ["content"]
            - name: "Schedule"
              icon: "calendar"
              sections: ["scheduling"]
            - name: "Workflow"
              icon: "git-branch"
              sections: ["workflow"]
              show_when:
                setting: "approval_workflow_enabled"
            - name: "Performance"
              icon: "bar-chart"
              sections: ["metrics"]
              show_when:
                field: "status"
                equals: "published"
          
        - type: "calendar"
          name: "Content Calendar"
          date_field: "scheduled_for"
          title_field: "title"
          color_field: "status"
          
        - type: "kanban"
          name: "Workflow Board"
          column_field: "status"
          card_fields: ["title", "platforms", "scheduled_for"]
      
      actions:
        - name: "Submit for Review"
          icon: "send"
          style: "primary"
          show_when:
            field: "status"
            equals: "draft"
          behavior:
            type: "update_and_notify"
            updates:
              status: "pending_review"
            notify:
              role: "approver"
              template: "post_pending_review"
              
        - name: "Approve"
          icon: "check"
          style: "success"
          show_when:
            field: "status"
            equals: "pending_review"
          requires_role: "approver"
          behavior:
            type: "update_and_notify"
            updates:
              status: "approved"
            notify:
              role: "creator"
              template: "post_approved"
              
        - name: "Reject"
          icon: "x"
          style: "danger"
          show_when:
            field: "status"
            equals: "pending_review"
          requires_role: "approver"
          behavior:
            type: "modal_form"
            fields: ["reviewer_notes"]
            on_submit:
              type: "update_and_notify"
              updates:
                status: "rejected"
              notify:
                role: "creator"
                template: "post_rejected"
                
        - name: "Schedule"
          icon: "calendar"
          style: "primary"
          show_when:
            field: "status"
            equals: "approved"
          behavior:
            type: "modal_form"
            fields: ["scheduled_for", "auto_publish"]
            on_submit:
              type: "update"
              updates:
                status: "scheduled"
                
        - name: "AI Write"
          icon: "sparkles"
          style: "outline"
          location: "field"  # Appears next to content field
          target_field: "content"
          behavior:
            type: "agent_assist"
            agent: "app_assistant"
            prompt: "Help me write this social media post"
      
      tools:
        - name: "create_post"
          description: "Create a new social media post"
          parameters:
            - name: "title"
              type: "string"
              required: true
            - name: "content"
              type: "string"
              required: true
            - name: "platforms"
              type: "array"
              required: true
          
        - name: "schedule_post"
          description: "Schedule a post for publishing"
          parameters:
            - name: "post_id"
              type: "integer"
              required: true
            - name: "scheduled_for"
              type: "datetime"
              required: true
              
        - name: "analyze_post_performance"
          description: "Get performance metrics for a post"
          parameters:
            - name: "post_id"
              type: "integer"
              required: true

    - name: "Media Library"
      slug: "media_library"
      description: "Store and organize images and videos"
      # ... fields, canvases, actions
      
    - name: "Campaigns"
      slug: "campaigns"
      description: "Group posts into marketing campaigns"
      relationships:
        - type: "has_many"
          target: "posts"
          foreign_key: "campaign_id"
  
  workflows:
    - name: "Auto-Publish Scheduled Posts"
      trigger:
        type: "scheduled"
        cron: "*/5 * * * *"  # Every 5 minutes
      conditions:
        - field: "status"
          equals: "scheduled"
        - field: "scheduled_for"
          less_than: "now"
        - field: "auto_publish"
          equals: true
      actions:
        - type: "for_each_matching"
          do:
            - type: "call_integration"
              integration: "platforms"
              operation: "publish"
            - type: "update"
              updates:
                status: "published"
                published_at: "now"
            - type: "notify"
              role: "creator"
              template: "post_published"
              
    - name: "Daily Performance Sync"
      trigger:
        type: "scheduled"
        cron: "0 6 * * *"  # Daily at 6am
      actions:
        - type: "for_each"
          model: "posts"
          where:
            status: "published"
            published_at:
              greater_than: "30 days ago"
          do:
            - type: "call_integration"
              integration: "platforms"
              operation: "get_metrics"
            - type: "update"
              from_result: true
  
  app_assistant:
    name: "Social Media Strategist"
    slug: "social_media_strategist"
    icon: "trending-up"
    
    persona: |
      You are a social media expert who helps users create engaging content.
      You understand platform best practices (LinkedIn is professional,
      Instagram is visual, Twitter is concise, etc.).
      
    capabilities:
      - name: "Write Posts"
        description: "Generate engaging social media content"
        prompt_template: |
          Create a {platform} post about {topic}.
          Tone: {tone}
          Include: {include_elements}
          
      - name: "Suggest Posting Times"
        description: "Recommend optimal times to post"
        uses_tool: "analyze_audience_activity"
        
      - name: "Analyze Performance"
        description: "Review what's working and suggest improvements"
        uses_tool: "analyze_post_performance"
        
      - name: "Generate Content Calendar"
        description: "Create a week/month of content ideas"
        prompt_template: |
          Create a {duration} content calendar for {platforms}.
          Business: {business_context}
          Goals: {goals}
    
    tools:
      - "create_post"
      - "schedule_post"
      - "analyze_post_performance"
      - "get_posts"
      - "update_post"
  
  integrations:
    - platform: "linkedin"
      operations:
        - "publish_post"
        - "get_metrics"
        - "get_company_page"
    - platform: "facebook"
      operations:
        - "publish_post"
        - "get_metrics"
```

### Blueprint Review Canvas

Users can review and modify the blueprint visually:

```
┌─────────────────────────────────────────────────────────────────────┐
│  📱 Social Media Manager - Blueprint Review                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─ Modules ──────────────────────────────────────────────────────┐ │
│  │                                                                 │ │
│  │  📝 Posts          📁 Media Library    📊 Campaigns            │ │
│  │  15 fields         8 fields            6 fields                │ │
│  │  4 views           2 views             3 views                 │ │
│  │  5 actions         3 actions           2 actions               │ │
│  │  [Edit] [Remove]   [Edit] [Remove]     [Edit] [Remove]         │ │
│  │                                                                 │ │
│  │  [+ Add Module]                                                 │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌─ Workflows ────────────────────────────────────────────────────┐ │
│  │  ⚡ Auto-Publish Scheduled Posts (every 5 min)                  │ │
│  │  📊 Daily Performance Sync (6am daily)                          │ │
│  │  [+ Add Workflow]                                               │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌─ App Assistant ────────────────────────────────────────────────┐ │
│  │  🤖 Social Media Strategist                                     │ │
│  │  Capabilities: Write Posts, Suggest Times, Analyze, Calendar   │ │
│  │  [Configure]                                                    │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌─ Integrations ─────────────────────────────────────────────────┐ │
│  │  🔗 LinkedIn    🔗 Facebook    [+ Add Integration]              │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  [🔙 Back to Discovery]  [👁 Preview App]  [🚀 Build App]       │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Phase 3: Build

### Agents Involved

1. **Module Builder Agent**
   - Generates database migrations
   - Creates model code
   - Generates canvas templates
   - Creates tool definitions

2. **Coding Agent** (for complex customizations)
   - Writes custom Ruby code
   - Creates custom JavaScript
   - Implements complex business logic

3. **Workflow Builder** (existing)
   - Creates scheduled tasks
   - Sets up automations

### Build Process

```
Blueprint ──▶ Module Builder Agent
                    │
                    ├──▶ Generate Migrations
                    ├──▶ Generate Model Code  
                    ├──▶ Generate Canvases
                    ├──▶ Generate Tools
                    ├──▶ Generate Actions
                    │
                    ▼
              Coding Agent (if needed)
                    │
                    ├──▶ Custom business logic
                    ├──▶ Complex validations
                    ├──▶ Integration glue code
                    │
                    ▼
              Create App Assistant
                    │
                    ├──▶ Generate agent plugin
                    ├──▶ Assign tools
                    ├──▶ Set persona/prompt
                    │
                    ▼
              Create Workflows
                    │
                    ├──▶ Scheduled tasks
                    ├──▶ Automations
                    │
                    ▼
              Ready for Testing
```

---

## Phase 4: Test & Iterate

### Preview Mode

- App runs in "preview" mode
- Changes don't affect production data
- User can test all functionality
- Amos helps identify issues

### Iteration Loop

```
User: "The 'Approve' button should also notify the content creator"

App Assistant: "I'll update the Approve action to send a notification.
              [Updates blueprint and regenerates action]
              ✅ Done! The creator will now receive a notification when approved."

User: "I also want to see the post content on the calendar, not just the title"

App Assistant: "I'll update the calendar view to show content preview.
              [Updates canvas configuration]
              ✅ Done! The calendar now shows a content snippet."
```

---

## Phase 5: Evolve

### Ongoing Development

Users can continue to enhance their app:

- **Add Fields**: "Add a 'utm_parameters' field to posts"
- **Add Views**: "Create a dashboard showing this week's scheduled posts"
- **Add Workflows**: "When a post gets 1000 impressions, notify me"
- **Add Integrations**: "Connect to Buffer for scheduling"
- **Enhance Assistant**: "Teach the assistant to generate image prompts for DALL-E"

---

## Data Models

### App

```ruby
class App < ApplicationRecord
  belongs_to :entity
  has_many :app_modules, dependent: :destroy
  has_many :app_workflows, dependent: :destroy
  has_one :app_assistant, class_name: 'AgentPlugin', as: :owner
  
  # Blueprint storage
  jsonb :blueprint  # Full design specification
  jsonb :intent     # Discovery results
  
  enum status: {
    designing: 'designing',      # In discovery/design phase
    building: 'building',        # Being generated
    preview: 'preview',          # Ready for testing
    active: 'active',            # Live
    archived: 'archived'
  }
end
```

### AppModule (Enhanced)

```ruby
class AppModule < ApplicationRecord
  belongs_to :app, optional: true  # Can be standalone or part of app
  belongs_to :entity
  
  # Enhanced configuration
  jsonb :field_config     # Sections, visibility, conditions
  jsonb :canvas_config    # Layouts, tabs, actions
  jsonb :action_config    # Button definitions
  jsonb :tool_config      # Auto-generated tools
end
```

### Action (New)

```ruby
class ModuleAction < ApplicationRecord
  belongs_to :app_module
  
  string :name
  string :icon
  string :style  # primary, secondary, success, danger, outline
  string :location  # toolbar, row, field
  
  jsonb :show_when      # Conditions
  jsonb :requires_role  # Permissions
  jsonb :behavior       # What happens when clicked
end
```

---

## Agent Architecture

### Agent Hierarchy for App Development

```
Amos (Scout)
  │
  ├── App Architect Agent
  │     └── Handles discovery and blueprint creation
  │
  ├── Module Builder Agent
  │     └── Generates code, tables, canvases
  │
  ├── Coding Agent
  │     └── Custom code for complex requirements
  │
  └── [Per-App] App Assistants
        └── Social Media Strategist
        └── Inventory Manager
        └── Project Tracker
        └── (dynamically created per app)
```

### App Assistant Generation

When an app is built, we automatically create an agent:

```ruby
def create_app_assistant(app, blueprint)
  AgentPlugin.create!(
    name: blueprint.dig('app_assistant', 'name'),
    slug: "app_#{app.slug}_assistant",
    description: "AI assistant for #{app.name}",
    
    # Persona from blueprint
    system_prompt: generate_assistant_prompt(app, blueprint),
    
    # Tools specific to this app
    tool_allowlist: blueprint.dig('app_assistant', 'tools'),
    
    # Can be invoked by Amos for this app
    invokable: true,
    agent_role: 'app_assistant',
    
    entity: app.entity,
    owner: app
  )
end
```

---

## Integration with Existing Platform

### Canvas System

- Uses existing canvas infrastructure
- New canvas types: `calendar`, `kanban`, `form_wizard`
- Enhanced form renderer respects new config

### Tool System

- Auto-generates tools for each module (CRUD + custom)
- Tools are scoped to app
- Registered in ToolCatalog automatically

### Workflow System

- Uses existing ScheduledAgentTask
- Adds new trigger types (field change, record created)
- Integrates with existing notification system

### Agent System

- App assistants are AgentPlugins
- Can be delegated to by Amos
- Have scoped tool access

---

## Implementation Priority

### Week 1: Foundation
- [ ] App model and migrations
- [ ] AppBlueprint model
- [ ] Enhanced field configuration schema
- [ ] App Architect agent (basic discovery)

### Week 2: Build System
- [ ] Enhanced Module Builder
- [ ] Form renderer with sections/visibility
- [ ] Action system
- [ ] Tool auto-generation

### Week 3: App Assistants
- [ ] App Assistant creation
- [ ] Per-app tool scoping
- [ ] Integration with Amos delegation

### Week 4: Polish
- [ ] Blueprint Review canvas
- [ ] Calendar view
- [ ] Kanban view
- [ ] Preview mode

### Week 5: Reference App
- [ ] Build Social Media Manager using the system
- [ ] Document patterns and best practices
- [ ] Create template library

---

## Success Metrics

1. **User can build a functional app in < 30 minutes** through conversation
2. **No code required** for 80% of use cases
3. **App quality matches custom development** for common patterns
4. **Users prefer our platform over general tools** for business apps
5. **Apps include working AI assistants** that genuinely help users





