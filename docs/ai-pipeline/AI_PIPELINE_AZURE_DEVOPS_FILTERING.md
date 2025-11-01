# AI Pipeline - Azure DevOps Filtering Configuration

**Last Updated**: January 29, 2025

This guide shows how to configure ticket filtering specifically for **Azure DevOps Work Items**.

---

## 🎯 Azure DevOps vs JIRA Field Mapping

The filtering uses generic field names that map to both systems:

| Generic Field | JIRA | Azure DevOps |
|--------------|------|--------------|
| `status` | Status | State |
| `issue_type` | Issue Type | Work Item Type |
| `labels` | Labels | Tags |
| `components` | Components | Area Path |
| `assignee` | Assignee | Assigned To |
| `priority` | Priority | Priority |

---

## 🔧 Azure DevOps Configuration

### Conservative Setup (Recommended Start)

```ruby
# Find your Azure DevOps connection
devops = McpConnection.find_by(
  system_type: 'azure_devops',
  name: 'Azure DevOps - Your Project'
)

# Configure filters for Azure DevOps
devops.update!(
  metadata: {
    pipeline_filters: {
      # Azure DevOps States
      allowed_statuses: [
        'New',           # If your "New" means "ready to start"
        'Approved',      # After requirements review
        'Committed'      # Selected for sprint
      ],

      # Azure DevOps Work Item Types
      allowed_issue_types: [
        'User Story',
        'Task',
        'Feature'
      ],

      # Azure DevOps Tags (opt-in approach)
      require_label: 'ai-pipeline',  # Optional: Only items with this tag

      # Exclude blocked work
      exclude_labels: [
        'Blocked',
        'On Hold',
        'Needs Discussion',
        'Manual Only',
        'No AI'
      ],

      # Assignee filter
      assignee_filter: 'unassigned'  # or 'any' or specific username
    }
  }
)
```

---

## 📋 Azure DevOps Workflow Examples

### Example 1: Scrum Board

**Your Workflow**:
```
New → Approved → Committed ✅ → Active → Resolved → Closed
```

**Configuration**:
```ruby
{
  allowed_statuses: ['Committed'],  # Only pick up sprint-committed items
  allowed_issue_types: ['User Story', 'Task'],
  exclude_labels: ['Blocked'],
  assignee_filter: 'unassigned'
}
```

**Result**: Only processes work items that are committed to the sprint but not yet assigned.

### Example 2: Kanban Board

**Your Workflow**:
```
Backlog → Ready ✅ → In Progress → Testing → Done
```

**Configuration**:
```ruby
{
  allowed_statuses: ['Ready'],  # Only items in Ready column
  allowed_issue_types: ['User Story', 'Task', 'Bug'],
  exclude_labels: ['Blocked', 'Waiting'],
  assignee_filter: 'unassigned'
}
```

### Example 3: Bug Workflow

**Your Workflow**:
```
Active → Triaged ✅ → Resolved → Closed
```

**Configuration** (for bugs only):
```ruby
{
  allowed_statuses: ['Triaged'],  # Only triaged bugs
  allowed_issue_types: ['Bug'],
  exclude_labels: ['Needs Investigation', 'Cannot Reproduce'],
  assignee_filter: 'unassigned'
}
```

---

## 🏷️ Azure DevOps Tags (Labels)

Azure DevOps uses **Tags** instead of Labels. The filtering works the same:

### Opt-In Approach (Recommended)

```ruby
{
  require_label: 'ai-pipeline',  # Only work items with this tag
  # ... other filters
}
```

**In Azure DevOps**:
1. Open work item
2. Add tag: `ai-pipeline`
3. Move to "Ready" state
4. Pipeline will pick it up

### Exclude Approach

```ruby
{
  exclude_labels: ['manual-only', 'complex', 'infrastructure'],
  # ... other filters
}
```

**In Azure DevOps**:
- Tag with `manual-only` to prevent AI processing
- Tag with `no-ai` to permanently exclude

---

## 🎯 Work Item Types

Azure DevOps has different work item types than JIRA:

### Standard Work Item Types

```ruby
allowed_issue_types: [
  'User Story',    # ✅ User stories
  'Task',          # ✅ Development tasks
  'Feature',       # ✅ Features
  'Bug',           # ✅ Bugs (after triage)
  'Issue'          # ✅ General issues
]

# Usually SKIP these:
# - 'Epic' (too large)
# - 'Test Case' (not development work)
```

### Process-Specific Types

Different Azure DevOps process templates have different types:

**Agile Process**:
- User Story, Task, Bug, Epic, Issue, Test Case

**Scrum Process**:
- Product Backlog Item, Task, Bug, Epic, Impediment, Test Case

**CMMI Process**:
- Requirement, Task, Bug, Epic, Change Request, Review, Risk, Issue

**Configuration Example**:
```ruby
# For Scrum process
allowed_issue_types: [
  'Product Backlog Item',  # Instead of User Story
  'Task',
  'Bug'
]
```

---

## 📍 Area Path Filtering (Components)

Azure DevOps uses **Area Paths** for organizing work. You can filter by area:

```ruby
{
  allowed_components: [
    'MyProject\\Backend',
    'MyProject\\API',
    'MyProject\\Services'
  ],
  # Skips: Frontend, Mobile, Infrastructure areas
}
```

**Note**: Use double backslashes `\\` in Ruby strings for area paths.

---

## 🎨 Custom Field Filtering

Azure DevOps supports custom fields. You can use them for filtering:

### Example: Custom "Ready for AI" Field

**In Azure DevOps**:
1. Create custom boolean field: "Ready for AI"
2. Add to work item form
3. Set to `True` when ready

**Configuration**:
```ruby
{
  custom_field_check: {
    field: 'Custom.ReadyForAI',  # Custom field name
    value: true
  }
}
```

---

## 🚀 Complete Azure DevOps Example

Here's a full production-ready configuration:

```ruby
# Find your Azure DevOps connection
devops = McpConnection.find_by(
  system_type: 'azure_devops',
  name: 'Azure DevOps - Production'
)

# Configure comprehensive filtering
devops.update!(
  metadata: {
    pipeline_filters: {
      # Only committed sprint work
      allowed_statuses: [
        'Committed',
        'Approved',
        'Ready'
      ],

      # Scrum process work item types
      allowed_issue_types: [
        'Product Backlog Item',
        'Task',
        'Bug'  # Only if triaged
      ],

      # Opt-in with tag
      require_label: 'ai-dev',

      # Skip blocked or complex work
      exclude_labels: [
        'Blocked',
        'Complex',
        'Infrastructure',
        'Manual',
        'Spike'  # Research tasks
      ],

      # Only unassigned work items
      assignee_filter: 'unassigned',

      # Only Backend and API areas
      allowed_components: [
        'MyProject\\Backend',
        'MyProject\\API'
      ]
    }
  }
)
```

---

## 🧪 Testing Azure DevOps Filters

```ruby
# Get your connection
devops = McpConnection.find_by(system_type: 'azure_devops')

# Fetch work items
client = devops.client
work_items = client.fetch_recent_tickets(since: 1.day.ago)

# Test filters
job = TicketWatcherJob.new

work_items.each do |item|
  ready = job.send(:ticket_ready_for_pipeline?, item, devops)

  puts "#{ready ? '✅' : '❌'} #{item[:id]}: #{item[:title]}"
  puts "   State: #{item[:status]}"
  puts "   Type: #{item[:issue_type]}"
  puts "   Tags: #{item[:labels]&.join(', ')}"
  puts "   Area: #{item[:components]&.first}"
  puts "   Assigned To: #{item[:assignee] || 'Unassigned'}"
  puts
end
```

---

## 📊 Azure DevOps Queries

You can also use Azure DevOps Queries to pre-filter work items:

### Option 1: Query in Azure DevOps

Create a saved query in Azure DevOps:
```
Work Item Type = User Story
AND State = Committed
AND Assigned To = @Me
AND Tags Contains ai-pipeline
```

Then configure your Azure DevOps client to use this query.

### Option 2: Filter in Pipeline (Current Approach)

Use the `pipeline_filters` as shown above. This approach is more flexible and doesn't require managing queries in Azure DevOps.

---

## 🔄 State Name Mapping

Different Azure DevOps processes use different state names:

### Agile Process States
```ruby
allowed_statuses: [
  'New',
  'Active',     # In progress
  'Resolved',
  'Closed'
]
```

### Scrum Process States
```ruby
allowed_statuses: [
  'New',
  'Approved',   # After review
  'Committed',  # In sprint
  'Done'
]
```

### CMMI Process States
```ruby
allowed_statuses: [
  'Proposed',
  'Active',
  'Resolved',
  'Closed'
]
```

**Check your states**:
1. Go to Azure DevOps
2. Open a work item
3. Look at State dropdown
4. Use exact state names in `allowed_statuses`

---

## ⚡ Quick Start Checklist

- [ ] Find your Azure DevOps connection in database
- [ ] Identify your process type (Agile, Scrum, CMMI)
- [ ] Check exact State names in Azure DevOps
- [ ] Check Work Item Type names
- [ ] Create `ai-pipeline` tag in Azure DevOps (if using opt-in)
- [ ] Configure `pipeline_filters` in connection metadata
- [ ] Test with dry run (see testing section above)
- [ ] Tag 2-3 test work items with `ai-pipeline`
- [ ] Run `TicketWatcherJob.perform_now`
- [ ] Verify work items are picked up
- [ ] Monitor first few pipeline executions
- [ ] Gradually expand by adding more tags

---

## 🎯 Recommended Azure DevOps Setup

**Best Practice**:

1. **Create custom tag**: `ai-dev` or `ai-pipeline`
2. **Use Committed state**: Only process sprint-committed work
3. **Start with Stories/Tasks**: Skip bugs initially
4. **Exclude complex work**: Tag infrastructure/complex items as `manual`
5. **Unassigned only**: Let AI pick up unassigned work

**Configuration**:
```ruby
{
  allowed_statuses: ['Committed'],
  require_label: 'ai-dev',
  allowed_issue_types: ['Product Backlog Item', 'Task'],
  exclude_labels: ['Manual', 'Complex', 'Blocked'],
  assignee_filter: 'unassigned'
}
```

---

## 📚 Related Documentation

- [AI_PIPELINE_TICKET_FILTERING.md](AI_PIPELINE_TICKET_FILTERING.md) - General filtering guide
- [AI_PIPELINE_USAGE_GUIDE.md](AI_PIPELINE_USAGE_GUIDE.md) - Complete usage guide
- [AI_PIPELINE_SPEC.md](AI_PIPELINE_SPEC.md) - Technical specification

---

**Happy DevOps Automating! 🚀**
