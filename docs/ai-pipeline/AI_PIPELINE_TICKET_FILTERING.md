# AI Pipeline - Ticket Filtering Configuration

**Last Updated**: January 29, 2025

This guide explains how to configure the AI Pipeline to only pick up tickets that are ready for development.

---

## 🎯 Overview

The `TicketWatcherJob` includes **7 filtering strategies** to prevent picking up:
- Backlog items not ready for development
- Bugs that haven't been triaged
- Epics or planning tickets
- Blocked or on-hold work
- Tickets requiring human discussion

---

## 🔧 Configuration Methods

### Method 1: Per-Connection Configuration (Recommended)

Configure filters for each JIRA/Azure DevOps connection separately.

#### Via Rails Console

```ruby
# Find your JIRA connection
jira_connection = McpConnection.find_by(system_type: 'jira', name: 'JIRA - Your Project')

# Set custom pipeline filters
jira_connection.update!(
  metadata: {
    pipeline_filters: {
      # Strategy 1: Only pick up tickets in these statuses
      allowed_statuses: [
        'Ready for Development',
        'Ready for Dev',
        'Selected for Development'
      ],

      # Strategy 2: Require a specific label (opt-in approach)
      require_label: 'ai-pipeline',  # Only tickets with this label

      # Strategy 3: Only these issue types
      allowed_issue_types: [
        'Story',
        'Task',
        'Feature'
      ],

      # Strategy 4: Only specific components (optional)
      allowed_components: [
        'Backend',
        'API'
      ],

      # Strategy 5: Custom field check (optional)
      custom_field_check: {
        field: 'Ready for AI',  # Custom field name
        value: true             # Expected value
      },

      # Strategy 6: Exclude tickets with these labels
      exclude_labels: [
        'blocked',
        'on-hold',
        'needs-discussion',
        'manual-only',
        'no-ai'
      ],

      # Strategy 7: Assignee filter
      assignee_filter: 'unassigned'  # or 'any' or 'ai-bot-username'
    }
  }
)
```

#### Via Admin UI (Add to Connection Form)

Add this section to `/app/views/admin/pipeline_connections/new.html.erb` (after the config section):

```erb
<!-- Pipeline Filtering Configuration (for JIRA/Azure DevOps only) -->
<div id="pipeline_filters_section" style="display: none;">
  <hr class="my-4">
  <h5 class="mb-3">
    <i data-lucide="filter" style="width: 20px; height: 20px;"></i>
    Pipeline Ticket Filtering
  </h5>
  <p class="text-muted">Configure which tickets the AI Pipeline should automatically process</p>

  <div class="mb-3">
    <label class="form-label">Allowed Statuses (one per line)</label>
    <textarea
      name="mcp_connection[metadata][pipeline_filters][allowed_statuses]"
      class="form-control"
      rows="4"
      placeholder="Ready for Development&#10;Ready for Dev&#10;To Do&#10;Selected for Development"></textarea>
    <div class="form-text">Only tickets in these statuses will be picked up</div>
  </div>

  <div class="mb-3">
    <label class="form-label">Required Label (optional)</label>
    <input
      type="text"
      name="mcp_connection[metadata][pipeline_filters][require_label]"
      class="form-control"
      placeholder="e.g., ai-pipeline">
    <div class="form-text">If set, only tickets with this label will be processed</div>
  </div>

  <div class="mb-3">
    <label class="form-label">Allowed Issue Types (one per line)</label>
    <textarea
      name="mcp_connection[metadata][pipeline_filters][allowed_issue_types]"
      class="form-control"
      rows="4"
      placeholder="Story&#10;Task&#10;Feature&#10;Enhancement"></textarea>
    <div class="form-text">Skip Epics, Sub-tasks, Bugs (unless specified)</div>
  </div>

  <div class="mb-3">
    <label class="form-label">Excluded Labels (one per line)</label>
    <textarea
      name="mcp_connection[metadata][pipeline_filters][exclude_labels]"
      class="form-control"
      rows="4"
      placeholder="blocked&#10;on-hold&#10;needs-discussion&#10;manual-only&#10;no-ai"></textarea>
    <div class="form-text">Tickets with these labels will be skipped</div>
  </div>

  <div class="mb-3">
    <label class="form-label">Assignee Filter</label>
    <select name="mcp_connection[metadata][pipeline_filters][assignee_filter]" class="form-select">
      <option value="unassigned">Unassigned only</option>
      <option value="any">Any assignee</option>
      <option value="ai-bot">Assigned to AI bot</option>
    </select>
    <div class="form-text">Which tickets to pick up based on assignee</div>
  </div>
</div>

<script>
  // Show/hide pipeline filters based on system type
  document.getElementById('system_type_select').addEventListener('change', function() {
    const filtersSection = document.getElementById('pipeline_filters_section');
    const ticketSystems = ['jira', 'azure_devops'];

    if (ticketSystems.includes(this.value)) {
      filtersSection.style.display = 'block';
    } else {
      filtersSection.style.display = 'none';
    }
  });
</script>
```

---

## 📋 Filtering Strategies Explained

### 1. **Status-Based Filtering** (Most Important)

Only pick up tickets in specific workflow states.

**JIRA Workflow Example**:
```
Backlog → To Do → Ready for Dev ✅ → In Progress → Code Review → Done
```

**Configuration**:
```ruby
allowed_statuses: [
  'Ready for Development',
  'Ready for Dev',
  'To Do'  # If your "To Do" means "ready to start"
]
```

**Skips**:
- ❌ Backlog (not ready)
- ❌ In Progress (already being worked on)
- ❌ Code Review (already has code)
- ❌ Done (completed)

### 2. **Label-Based Filtering** (Opt-In Approach)

Require tickets to have a specific label like `ai-pipeline` or `auto-dev`.

**When to use**:
- Start small: Only AI-process tickets you explicitly tag
- Gradual rollout: Tag tickets as you're confident
- Team adoption: Let team choose which tickets go to AI

**Configuration**:
```ruby
require_label: 'ai-pipeline'
```

**JIRA Setup**:
1. Create label: "ai-pipeline"
2. Only add to tickets you want AI to handle
3. Gradually expand as confidence grows

### 3. **Issue Type Filtering**

Skip certain types like Epics, Sub-tasks, or Bugs.

**Configuration**:
```ruby
allowed_issue_types: [
  'Story',      # ✅ User stories
  'Task',       # ✅ Development tasks
  'Feature'     # ✅ New features
]
# Skips: Epic, Sub-task, Bug (by default)
```

**For Bugs** (if you want AI to handle them):
```ruby
allowed_issue_types: [
  'Story',
  'Task',
  'Feature',
  'Bug'  # ✅ Add this if you want AI to fix bugs
]

# But also add status filter to only get triaged bugs:
allowed_statuses: [
  'Ready for Development',  # Bugs move here after triage
  'Triaged'
]
```

### 4. **Component Filtering**

Only process tickets from specific components.

**Use case**: Start with backend/API, skip frontend

**Configuration**:
```ruby
allowed_components: [
  'Backend',
  'API',
  'Database'
]
# Skips: Frontend, Mobile, Infrastructure
```

### 5. **Custom Field Filtering**

Use a JIRA custom field as a gate.

**Setup in JIRA**:
1. Create custom field: "Ready for AI" (checkbox)
2. Add to ticket create/edit screens
3. Team checks box when ticket is ready

**Configuration**:
```ruby
custom_field_check: {
  field: 'Ready for AI',
  value: true
}
```

### 6. **Exclude Labels** (Blockers)

Skip tickets with blocking labels.

**Configuration**:
```ruby
exclude_labels: [
  'blocked',           # Waiting on something
  'on-hold',           # Paused work
  'needs-discussion',  # Requires human planning
  'manual-only',       # Never automate
  'no-ai',             # Explicit opt-out
  'spike',             # Research ticket
  'infrastructure'     # Complex infrastructure work
]
```

### 7. **Assignee Filtering**

Control who can "send" tickets to AI.

**Options**:

```ruby
# Option 1: Only unassigned tickets
assignee_filter: 'unassigned'
# Use case: Tickets in "Ready for Dev" backlog

# Option 2: Any assignee
assignee_filter: 'any'
# Use case: Anyone can assign to AI

# Option 3: Specific AI bot user
assignee_filter: 'ai-dev-bot'
# Use case: Assign to @ai-dev-bot to trigger pipeline
```

---

## 🎯 Recommended Configurations

### Conservative Approach (Start Here)

```ruby
{
  allowed_statuses: ['Ready for Development'],
  require_label: 'ai-pipeline',  # Explicit opt-in
  allowed_issue_types: ['Story', 'Task'],
  exclude_labels: ['blocked', 'manual-only', 'no-ai'],
  assignee_filter: 'unassigned'
}
```

**Result**: Only processes tickets that:
- ✅ Are in "Ready for Development" status
- ✅ Have the "ai-pipeline" label
- ✅ Are Story or Task type
- ✅ Don't have blocking labels
- ✅ Are unassigned

### Aggressive Approach (High Confidence)

```ruby
{
  allowed_statuses: [
    'Ready for Development',
    'Ready for Dev',
    'To Do'
  ],
  # No require_label - process all ready tickets
  allowed_issue_types: ['Story', 'Task', 'Feature', 'Bug'],
  exclude_labels: ['blocked', 'manual-only'],
  assignee_filter: 'any'
}
```

**Result**: Processes most tickets that are ready, regardless of label

### Bug-Only Configuration

```ruby
{
  allowed_statuses: ['Triaged', 'Ready for Fix'],
  allowed_issue_types: ['Bug'],
  exclude_labels: ['needs-investigation', 'manual-fix-required'],
  assignee_filter: 'unassigned'
}
```

**Result**: Only processes triaged bugs ready for fixing

---

## 🧪 Testing Your Filters

### Method 1: Dry Run in Console

```ruby
# Load the job
job = TicketWatcherJob.new

# Get your connection
connection = McpConnection.find_by(name: 'JIRA - Your Project')

# Fetch tickets
client = connection.client
tickets = client.fetch_recent_tickets(since: 1.day.ago)

# Test filters on each ticket
tickets.each do |ticket|
  ready = job.send(:ticket_ready_for_pipeline?, ticket, connection)
  status_icon = ready ? '✅' : '❌'

  puts "#{status_icon} #{ticket[:id]}: #{ticket[:title]}"
  puts "   Status: #{ticket[:status]}"
  puts "   Type: #{ticket[:issue_type]}"
  puts "   Labels: #{ticket[:labels]&.join(', ')}"
  puts "   Ready: #{ready}"
  puts
end
```

### Method 2: Enable Debug Logging

```ruby
# In config/environments/development.rb
config.log_level = :debug

# Run the job
TicketWatcherJob.perform_now

# Check logs
docker compose logs web --tail=100 | grep "Skipping ticket"
```

You'll see output like:
```
⏭️  Skipping ticket PROJ-123: Not ready for AI pipeline
⏭️  Skipping ticket PROJ-456: Not ready for AI pipeline
📋 Created pipeline execution 789 for ticket PROJ-789
```

---

## 🔄 Updating Filters

### Update via Console

```ruby
connection = McpConnection.find_by(name: 'JIRA - Your Project')

# Get current filters
current_filters = connection.metadata['pipeline_filters']

# Update just one setting
current_filters['require_label'] = 'ai-dev'  # Change label requirement
connection.update!(metadata: connection.metadata)

# Or replace entirely
connection.update!(
  metadata: {
    pipeline_filters: {
      # New configuration
    }
  }
)
```

### Update via Admin UI

1. Go to Admin → Pipeline → Connections
2. Click "Edit" on your connection
3. Modify filter settings
4. Click "Save"

---

## 📊 Monitoring Filter Effectiveness

### Check What's Being Processed

```ruby
# Last 24 hours
PipelineExecution.where('created_at > ?', 24.hours.ago)
  .pluck(:ticket_id, :ticket_title, :ticket_system, :status)

# Count by status
PipelineExecution.group(:status).count
```

### Check What's Being Skipped

Enable debug logging and grep for "Skipping":

```bash
docker compose logs web --since=1h | grep "Skipping ticket" | wc -l
# Shows how many tickets were filtered out
```

---

## 🚨 Common Pitfalls

### Pitfall 1: Too Restrictive Filters

**Problem**: No tickets being picked up

**Check**:
```ruby
connection = McpConnection.find_by(name: 'JIRA - Your Project')
filters = connection.metadata['pipeline_filters']

puts "Allowed statuses: #{filters['allowed_statuses']}"
puts "Required label: #{filters['require_label']}"
```

**Fix**: Loosen one filter at a time:
1. Remove `require_label` temporarily
2. Add more `allowed_statuses`
3. Add more `allowed_issue_types`

### Pitfall 2: Status Name Mismatch

**Problem**: Your JIRA uses "Ready" but filter says "Ready for Development"

**Fix**: Check exact status names:
```ruby
tickets = client.fetch_recent_tickets(since: 1.day.ago)
tickets.each { |t| puts t[:status] }
```

Then update to match exact names (case-insensitive).

### Pitfall 3: Labels Not Syncing

**Problem**: JIRA labels not showing up in `ticket[:labels]`

**Fix**: Check the JIRA client mapping:
```ruby
# In your JIRA client implementation
ticket[:labels] = jira_issue.labels  # Make sure this is populated
```

---

## 🎓 Best Practices

1. **Start Conservative**: Use `require_label` initially, gradually remove
2. **Monitor First Week**: Check logs daily to see what's picked up
3. **Team Communication**: Tell team about the labels/statuses that trigger AI
4. **Gradual Rollout**: Start with one project, expand to others
5. **Document Filters**: Add comment in connection metadata explaining why
6. **Test in Staging**: Create test tickets with various statuses/labels
7. **Feedback Loop**: Review failed pipelines to improve filters

---

## 📚 Related Documentation

- [AI_PIPELINE_USAGE_GUIDE.md](AI_PIPELINE_USAGE_GUIDE.md) - General usage
- [AI_PIPELINE_HOW_IT_WORKS.md](AI_PIPELINE_HOW_IT_WORKS.md) - Workflow details
- [AI_PIPELINE_SPEC.md](AI_PIPELINE_SPEC.md) - Technical specification

---

**Happy Filtering! 🎯**
