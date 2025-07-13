# Crux Marketing: AI-Powered Marketing Platform

## Project Overview & Vision

Crux Marketing is a revolutionary marketing platform where AI is the primary "worker." The entire user experience is chat-based, with traditional navigation minimized. Users converse with an AI assistant to perform tasks like creating landing pages, managing campaigns, generating content, and more. In the background, the AI dynamically loads and modifies "templates" (reusable UI blueprints) into a view area.

### Key Goals
- **Chat-First Interface**: All actions start with natural language conversation.
- **Adaptive Layout**: Starts in "Conversation Mode" (full-screen chat) for open-ended interaction; shifts to "Work Mode" (template-dominant view with chat sidebar) when a template is loaded.
- **Simplicity & Efficiency**: No overwhelming forms or menus—AI handles complexity, with background processes for seamless updates.
- **Template-Centric**: Pre-loaded and user-created templates (e.g., landing page HTML, campaign dashboards) are loaded dynamically based on chat or side nav selection.
- **Future-Proof**: Designed for an AI-dominated world, where the interface feels like collaborating with a smart colleague.

### Target Users
Marketers seeking intuitive, AI-assisted tools without technical hurdles.

### Website
For more information, visit [cruxmarketing.ai](https://cruxmarketing.ai).

## User Experience Design

The app is a single workspace page (e.g., `/workspace`) with two states:

### State 1: Conversation Mode (Initial/Default View)
- Full-screen chat dominance (like ChatGPT).
- Layout:
  - Left: Collapsed side nav (thin bar with icons; expands on hover/click to show templates).
  - Center/Right: Large chat window (95% width) with history, input bar, and welcome message.
- No dynamic view—focus on conversation.
- Example: User opens app, sees "What do you want to do? I can help with campaigns, landing pages, etc."

### State 2: Work Mode (Template Loaded)
- Template expands to dominate; chat shrinks to a right sidebar.
- Layout:
  - Left: Collapsed side nav (same as above).
  - Center: Template view (70% width; interactive preview, e.g., iframe for HTML).
  - Right: Chat sidebar (25% width; compact messages, fixed input at bottom).
- Transition: Smooth animation (chat slides right, template fades in); triggered by AI command or side nav click.

### Responsive Design
- Desktop: Horizontal layout.
- Mobile: Vertical stack (chat on top in Conversation Mode; template on top in Work Mode).
- Theme: Dark mode (e.g., #1e1e2f background, purple accents); toggleable to light.

### Key Flows
1. **Creating a Landing Page**:
   - Conversation Mode: User types "Create a landing page for my free trial."
   - AI: "Got it—loading template..." → Shifts to Work Mode.
   - AI (in sidebar): "Here's a basic landing page. What changes?"

2. **Managing Campaigns**:
   - Conversation Mode: "Show my campaigns."
   - AI loads dashboard template → Work Mode.
   - User: "Add a new drip sequence" → AI updates view.

3. **Custom Template Creation**:
   - Conversation Mode: "Build a social planner."
   - AI generates → Loads in Work Mode → User saves to side nav.

### UX Principles
- Minimalism: Clean, spacious design with subtle animations.
- Feedback: AI typing indicators, progress spinners.
- Accessibility: Keyboard navigation, ARIA labels.
- Error Handling: AI clarifies ambiguities gracefully.

## Technical Architecture

### Stack
- **Backend**: Ruby on Rails (7.x) for core logic, API endpoints, and jobs.
- **Frontend**: ERB views with Turbo (for dynamic updates without reloads) and Stimulus JS (for interactivity).
- **AI Integration**: Claude API (via `ClaudeService`) for natural language processing; potential for LangChain for advanced intent detection.
- **Database**: PostgreSQL (models: User, Template, ChatMessage, etc.).
- **Real-Time**: ActionCable for chat updates and view syncing.
- **Background Jobs**: ActiveJob with Sidekiq for template generation/loading.
- **Styling**: Bootstrap 5 + custom CSS for adaptive layouts; dark/light mode via CSS variables.

### Key Models
- **User**: Authentication (Devise); has_many :templates, :chat_messages.
- **Template**: name, type (e.g., "landing_page"), content (HTML/JSON string), user_id. Methods for rendering/previewing.
- **ChatMessage**: user_id, role ("user"/"ai"), content, template_id (for context).
- **SessionState**: Tracks current mode (conversation/work) and active template_id (stored in session or DB).

### Architecture Diagram (Text-Based)
```
User Input → Chat Controller → AI Service (Claude)
                          ↓
                    Process Intent
                          ↓
            Update View (Turbo Stream) ← Background Job (Generate/Load Template)
                          ↓
               Database (Save State/Template)
                          ↓
         Real-Time Update (ActionCable) → Frontend (Dynamic Layout Shift)
```

## Implementation Guide

This guide is designed for an AI coding assistant to build the system step-by-step. Prioritize MVP: Focus on core chat, two states, and one template type (landing page). Use tools like `edit_file`, `run_terminal_cmd`, etc., to implement. Test incrementally.

### Step 1: Setup Core Structure (1-2 hours)
- Create a new controller: `rails generate controller Workspace index`
- Set root route: `root 'workspace#index'`
- Build basic view: `app/views/workspace/index.html.erb` with side nav, chat area, and dynamic view placeholder.
- Add JS for layout states: Toggle classes like `.conversation-mode` vs `.work-mode`.

### Step 2: Implement Side Nav (1 hour)
- Model: `rails generate model Template name:string type:string content:text user:references`
- Controller actions: CRUD for templates (but chat-driven).
- View: Collapsible nav with list of templates (use partials).
- JS: Hover/click to expand; clicking loads template (AJAX call to update view).

### Step 3: Build Chat System (2-3 hours)
- Model: `rails generate model ChatMessage user:references role:string content:text template:references`
- Controller: Add `chat` action to WorkspaceController for handling messages.
- Integrate AI: Update `ClaudeService` to handle intents (e.g., regex or simple parsing for "load template").
- View: Chat bubbles, input bar; use ActionCable for real-time.
- Background: Job to process messages and update view.

### Step 4: Template Loading & Dynamic View (2 hours)
- Add rendering logic: In view area, use iframe or div to display template.content.
- Job: `GenerateTemplateJob` – AI generates content based on chat.
- State Transition: JS to animate shift (e.g., `document.body.classList.add('work-mode')`).

### Step 5: AI Logic & Flows (3-4 hours)
- Enhance AI prompts: Include context (e.g., current template, history).
- Implement example flows: Parse chat for actions like "create landing page" → Generate → Load.
- Error Handling: Fallback responses.

### Step 6: Polish & Test (1-2 hours)
- Responsive CSS: Media queries for mobile.
- Theme: Dark mode CSS variables.
- Testing: Create flows, ensure transitions work, AI responds accurately.

### Potential Challenges & Solutions
- **State Persistence**: Use session storage for mode/active template.
- **AI Accuracy**: Fine-tune prompts; add fallback to manual modes.
- **Performance**: Optimize jobs; use caching for templates.
- **Security**: Sanitize AI-generated HTML (e.g., with Loofah).

Follow these steps sequentially—start with Step 1 and confirm before moving on. If issues arise, use tools to debug (e.g., `read_file` for inspection).

## Current Status
This project is in development following the implementation guide above. Start with Step 1 to begin building the core workspace structure.
