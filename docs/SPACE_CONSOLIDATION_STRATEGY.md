# Space Consolidation Strategy

## The Evolution of Thinking

**Original Problem:** Feature duplication across Work Inbox, Team Space, Chat, Design Space, Scheduling Canvas.

**Key Insight:** Everything is a canvas. Spaces are just mindsets + tool/canvas availability.

---

## The Three Space Model

### Core Principle: Canvas-First Architecture

A "Space" is NOT a different app. It's:
1. **A mindset** - What Amos is optimized for
2. **A tool loadout** - What capabilities are available  
3. **A canvas library** - What canvases can be loaded
4. **A context prompt** - How Amos behaves

The chat with Amos is ALWAYS there. The canvas area changes based on what you're doing.

---

## 🏠 Personal Space → "You & Amos"

**The Mindset:** Private thinking, personal productivity, research

**Available Canvases:**
- Notes canvas
- Bookmarks/reading list canvas
- Personal tasks canvas
- Document reader canvas
- Web research canvas

**Amos Role:** Your personal AI friend. No business tools, no agent delegation. Just thinking together.

**Key Behavior:** If you ask to "build something", Amos suggests: "Want to switch to Design mode for this?"

---

## ⚡ Operations Space → "Business HQ"

**The Mindset:** Running the business - viewing data, managing operations, coordinating work

**Available Canvases:**

| Canvas Type | Purpose |
|-------------|---------|
| **Data Canvas** | View/query contacts, campaigns, modules, etc. |
| **Analytics Canvas** | Charts, dashboards, metrics |
| **Collaboration Canvas** | Slack-like channels/DMs with agents and team |
| **Scheduled Tasks Canvas** | What's running, what's queued |
| **Deliveries Canvas** | Completed artifacts, visualizations, exports |
| **Integration Status Canvas** | Connection health, sync status |

**Amos Role:** Business assistant. Can query data, update records, show status. Orchestrates agents through the Collaboration Canvas.

**The Collaboration Canvas IS the Team/Slack feature.** It's just another canvas, not a separate space. When you need to see agent activity or answer agent questions, you load the Collaboration Canvas. When you need to see data, you load the Data Canvas. Same space, different views.

---

## 🎨 Design Space → "Creation Studio"

**The Mindset:** Building things with iterative feedback

**Available Canvases:**

| Canvas Type | Purpose |
|-------------|---------|
| **Application Plan Canvas** | Propose, refine, approve app designs |
| **Landing Page Editor** | Visual page editing |
| **Workflow Editor** | Visual automation design |
| **Component Gallery** | Browse/select components |
| **Preview Canvas** | Live preview of what you're building |
| **Design Collaboration Canvas** | Chat with design agents IN context |

**Amos Role:** Design partner. Works WITH you iteratively. Shows previews, accepts feedback, refines.

**CRITICAL:** Design is iterative. The back-and-forth with agents happens IN Design Space via the Design Collaboration Canvas. You don't switch to another space when an agent has a question about your design - the question appears right there in the design context.

---

## The UI Model

### Core Principle: Chat + Canvas + Optional Sidebar

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                               AMOS UI                                         │
├───────────┬─────────────────────────────┬────────────────────────────────────┤
│           │                             │                                     │
│  COLLAB   │        CHAT AREA            │          CANVAS AREA                │
│  SIDEBAR  │                             │                                     │
│           │  Amos is ALWAYS here.       │  Changes based on what's loaded.    │
│  (Only in │  The primary interface.     │  Visual feedback, editors, data.    │
│  Ops &    │  The constant.              │                                     │
│  Design)  │                             │  Click something in sidebar →       │
│           │  User types.                │  loads that agent/channel here.     │
│  Agents   │  Amos responds.             │                                     │
│  Team     │  Always conversational.     │  Or Amos loads canvases based       │
│  Channels │                             │  on what you're working on.         │
│           │                             │                                     │
└───────────┴─────────────────────────────┴────────────────────────────────────┘
```

### The Three Layouts

**🏠 Personal Mode:**
```
┌─────────────────────────────────┬───────────────────────────────────────┐
│                                 │                                        │
│         CHAT WITH AMOS          │            CANVAS AREA                 │
│                                 │                                        │
│  Just you and Amos.             │  Notes, bookmarks, research.           │
│  No sidebar.                    │  Personal canvases only.               │
│  No agents.                     │                                        │
│  Private thinking space.        │                                        │
│                                 │                                        │
└─────────────────────────────────┴───────────────────────────────────────┘
```

**⚡ Operations Mode:**
```
┌───────────┬─────────────────────────────┬────────────────────────────────────┐
│           │                             │                                     │
│  SIDEBAR  │        CHAT WITH AMOS       │          CANVAS AREA                │
│           │                             │                                     │
│  📧 Email │  Business operations chat.  │  Data tables, analytics,            │
│  🤖 Agents│  Query, manage, coordinate. │  deliveries, integrations.          │
│  👥 Team  │                             │                                     │
│  📅 Tasks │  "Show me contacts"         │  Click agent in sidebar →           │
│           │  "What's the pipeline?"     │  loads their channel here.          │
│  ─────    │                             │                                     │
│  #general │  Amos orchestrates.         │  See agent status, answer           │
│  #agents  │                             │  questions, review work.            │
│           │                             │                                     │
└───────────┴─────────────────────────────┴────────────────────────────────────┘
```

**🎨 Design Mode:**
```
┌───────────┬─────────────────────────────┬────────────────────────────────────┐
│           │                             │                                     │
│  SIDEBAR  │        CHAT WITH AMOS       │          CANVAS AREA                │
│           │                             │                                     │
│  🏗️ Planner│  Design conversation.      │  Application Plan preview,          │
│  🎨 Design│  Iterative back-and-forth. │  Landing Page Editor,               │
│  🔧 Module│                             │  Workflow Editor, Previews.         │
│           │  "Make the header bigger"   │                                     │
│  ─────    │  "Add a deals section"      │  Click agent in sidebar →           │
│  #design  │                             │  loads their channel here.          │
│  #current │  Amos is your design        │                                     │
│   project │  partner.                   │  See design agent feedback,         │
│           │                             │  answer questions in context.       │
└───────────┴─────────────────────────────┴────────────────────────────────────┘
```

---

## The Collaboration Sidebar

This is the key UI element that enables multi-agent coordination WITHOUT a separate space.

### Structure

```
┌─────────────────┐
│  🔍 Search      │
├─────────────────┤
│  AGENTS         │
│  ├─ 🤖 Landing  │  ← Click to load their channel
│  │     Page     │
│  ├─ 🤖 Module   │  ← Badge if they have a question
│  │     Arch  🔴 │
│  ├─ 🤖 Email    │
│  │     Expert   │
│  └─ 🤖 Integ    │
│       Builder   │
├─────────────────┤
│  TEAM           │
│  ├─ 👤 Rick     │
│  ├─ 👤 Sarah    │
│  └─ 👤 Mike     │
├─────────────────┤
│  CHANNELS       │
│  ├─ # general   │
│  ├─ # agents 🔴 │  ← Unread activity
│  └─ # design    │
├─────────────────┤
│  CURRENT WORK   │
│  ├─ 📋 CRM      │  ← Active design project
│  │    Build     │
│  └─ 📋 Landing  │
│       Page V2   │
└─────────────────┘
```

### Sidebar Availability

| Mode | Sidebar? | Why |
|------|----------|-----|
| Personal | ❌ No | Just you and Amos. Private space. |
| Operations | ✅ Yes | Coordinate with agents and team for business ops |
| Design | ✅ Yes | Collaborate with design agents on current project |

### What Clicking Does

- **Click Agent** → Loads their channel/DM in canvas area. See their activity, pending questions, recent work.
- **Click Team Member** → Loads DM with them
- **Click Channel** → Loads channel feed in canvas area
- **Click Current Work** → Loads that project's context (agents involved, status, preview)

---

## What Changes

### Work Inbox → Deliveries Canvas
The Work Inbox becomes just another canvas in Operations Space. It shows completed artifacts - things agents made FOR you. No more agent questions here (those are in Collaboration Canvas).

### Team Space → Collaboration Canvas
The whole "Team" space concept becomes a canvas type that can load in Operations OR Design. In Operations, it's for general agent coordination. In Design, it's embedded for design-specific collaboration.

### Scheduling Canvas → Stays, but in Operations
Scheduled tasks are part of Operations. The canvas loads there.

### Design Space → Self-Contained Iteration
Design handles its entire lifecycle:
1. User describes what they want
2. Amos (with Application Planner) creates a plan
3. Plan appears in Application Plan Canvas
4. User gives feedback ("make the CRM also track deals")
5. Plan updates
6. User approves
7. Build happens (progress shown in Design Space)
8. If agents need input → Design Collaboration Canvas shows question
9. User answers IN Design Space
10. Build completes → Result previews in Preview Canvas
11. User can then switch to Operations to see it in their data

**No space switching during design workflow.**

---

## The Collaboration Canvas Deep Dive

Since this is becoming a key canvas type, let's define it:

### Features
- **Channels**: One per agent type (Landing Page Agent, Module Architect, etc.)
- **DMs**: Direct messages with specific agents
- **Activity Feed**: Real-time updates on what agents are doing
- **Question Queue**: Pending questions from agents (with badges)
- **Task Status**: Current running tasks, queued tasks

### Where It Loads
- **Operations Space**: Full collaboration view for all agent activity
- **Design Space**: Filtered to design-relevant agents and current project

### Visual Style
- Familiar Slack-like UI (channels, messages, threading)
- But it's a canvas, not a full page
- Can be split-viewed with other canvases

---

## Agent Questions - The New Flow

**Current:** Agent question → Badge in Work Inbox → Modal popup → Answer → Modal closes

**New Flow:**

```
Agent has question
       │
       ▼
┌─────────────────────────────────────────┐
│  If in Design Space:                    │
│    → Question appears in Design         │
│      Collaboration Canvas               │
│    → Inline with design context         │
│    → User answers without leaving       │
└─────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│  If in Operations Space:                │
│    → Collaboration Canvas shows badge   │
│    → User loads canvas, sees question   │
│    → User answers in thread             │
└─────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│  If in Personal Space:                  │
│    → Space icon shows badge             │
│    → "An agent has a question"          │
│    → User clicks to switch to           │
│      Operations or Design               │
└─────────────────────────────────────────┘
```

---

## Implementation: What Stays, What Changes

### Keep As-Is
- Chat with Amos (the constant, always-present core)
- Canvas loading mechanism
- Space switcher UI (but now 3 modes: Personal, Operations, Design)
- Most individual canvas implementations

### Consolidate/Remove
- **Work Inbox** → becomes "Deliveries Canvas" (one of many canvases)
- **Team Space** → eliminated as separate space; becomes the Collaboration Sidebar
- **Scheduling Canvas standalone** → becomes a canvas loadable via sidebar
- **Separate agent question modal** → questions show as sidebar badge, answered in canvas

### New Development
- **Collaboration Sidebar Component** - The Slack-like sidebar for Ops & Design
- **Deliveries Canvas** - Simplified Work Inbox showing completed artifacts
- **Project Context in Sidebar** - "Current Work" section showing active projects

---

## The Critical Insight

**The Collaboration Sidebar is NOT a space. It's a UI component.**

Available in:
- ✅ Operations Mode
- ✅ Design Mode
- ❌ Personal Mode (no sidebar - just you and Amos)

This means:
- When in Design, you can talk to design agents via sidebar WITHOUT leaving design
- When in Operations, you can coordinate with all agents via sidebar
- When in Personal, you're alone with Amos - no agents, no team, no sidebar

---

## Agent Questions - Final Flow

```
Agent has a question during design work
                │
                ▼
┌─────────────────────────────────────────────────────────────┐
│  User is in Design Mode                                     │
│                                                             │
│  Sidebar shows:  🤖 Module Architect 🔴                     │
│                                                             │
│  User clicks agent in sidebar                               │
│                                                             │
│  Canvas loads agent channel with question:                  │
│  "Should the Deals module include forecasting?"             │
│                                                             │
│  User types answer in canvas (or in main chat)              │
│                                                             │
│  Agent continues work                                       │
│                                                             │
│  User clicks back to their design canvas                    │
│  (or sidebar "Current Work" → their project)                │
└─────────────────────────────────────────────────────────────┘
```

**No space switching. Everything in context.**

---

## Benefits of This Model

1. **One place, one context** - Stay in your mode, load what you need in canvas
2. **Familiar Slack metaphor** - Sidebar for navigation, content area for work
3. **No interruption** - Agent questions appear as sidebar badges, not modal popups
4. **Scales naturally** - More agents = more sidebar items, not more UI complexity
5. **Personal mode is truly personal** - No work intrusions
6. **Design mode is self-contained** - Full iteration cycle without leaving

---

## Migration Path

### Phase 1: Build Collaboration Sidebar (Week 1-2) ✅ COMPLETE
- [x] Create sidebar component with agents, team, channels sections
- [x] Sidebar loads agent channel into canvas area on click
- [x] Badge system for unread/questions
- [x] Conditional rendering: show only in Ops & Design modes

### Phase 2: Collapse to 3 Modes (Week 2-3) ✅ COMPLETE
- [x] Merge Work + Team into Operations mode
- [x] Update space definitions (Personal, Operations, Design)
- [x] Update Amos context prompts per mode
- [x] Update tool loadouts per mode
- [x] Personal mode: hide sidebar entirely

### Phase 3: Integrate Agent Questions into Sidebar (Week 3-4) ✅ COMPLETE
- [x] Agent questions → sidebar badge on that agent (yellow ? indicator)
- [x] Click agent → see their questions in canvas
- [x] Answer inline, agent receives response
- [x] API endpoints: agent_questions, answer_agent_question, skip_agent_question

### Phase 4: Polish & Test (Week 4-5) 🔄 IN PROGRESS
- [x] "Current Work" section in sidebar (shows active plans, landing pages)
- [x] Deliveries section (Operations mode only)
- [ ] Test full user journeys in each mode
- [ ] Remove legacy Work Inbox question badge
- [ ] Documentation

---

## Technical Notes

### Sidebar Component
```erb
<%# Only render sidebar in Operations and Design modes %>
<% if current_space.in?(['operations', 'design']) %>
  <%= render 'scout/collaboration_sidebar' %>
<% end %>
```

### Sidebar Data Structure
```ruby
# What the sidebar needs to display
{
  agents: [
    { id: 1, name: "Landing Page Agent", slug: "landing_page_agent", 
      unread: 0, has_question: false },
    { id: 2, name: "Module Architect", slug: "module_architect",
      unread: 3, has_question: true },
    # ...
  ],
  team: [
    { id: 1, name: "Rick", avatar: "...", status: "online" },
    # ...
  ],
  channels: [
    { id: 1, name: "general", unread: 0 },
    { id: 2, name: "agents", unread: 5 },
    # ...
  ],
  current_work: [
    { id: 1, type: "application_plan", name: "CRM Build", status: "building" },
    { id: 2, type: "landing_page", name: "Launch Page", status: "draft" },
    # ...
  ]
}
```

### Loading Content from Sidebar Click
```javascript
// When user clicks an agent in sidebar
sidebarController.loadAgentChannel(agentId) {
  // Load the agent's channel/DM into the canvas area
  this.loadCanvas('agent_channel', { agent_id: agentId })
}

// When user clicks "Current Work" item
sidebarController.loadProject(projectId, projectType) {
  // Load the appropriate canvas for that project
  this.loadCanvas(projectType + '_editor', { id: projectId })
}
```

---

## Summary

**Before:** 4 spaces with duplicated features and confusing handoffs
**After:** 3 modes + a collaboration sidebar that appears in 2 of them

```
┌──────────────────────────────────────────────────────────────┐
│                                                               │
│   🏠 Personal       ⚡ Operations       🎨 Design            │
│   ───────────       ──────────────      ─────────            │
│   No sidebar        Has sidebar         Has sidebar          │
│   Just Amos         Agents + Team       Design agents        │
│   Private           Business ops        Creation             │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

**Chat is the core. Canvas is the context. Sidebar is the navigation.**
**Amos is always there. He adapts to your mode.**

