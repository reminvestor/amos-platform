# Extensible Agent Framework

**Version:** 1.0.0
**Status:** ✅ Production Ready
**Author:** Built with Claude Code

---

## 🎯 Overview

The Agent Framework provides a **database-backed, extensible system** for creating, deploying, and managing AI agents without code changes. This allows you to:

- ✅ Create custom agents via the admin UI
- ✅ Define agent capabilities with contracts
- ✅ Bind agents to specific workflow phases
- ✅ Track agent performance and usage
- ✅ Clone and customize existing agents
- ✅ A/B test different agent implementations

---

## 🏗️ Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                     Admin UI Layer                           │
│  /admin/agent_plugins - Create, Edit, Test, Analyze         │
└──────────────────────────────────┬──────────────────────────┘
                                   │
┌──────────────────────────────────▼──────────────────────────┐
│                  AgentPluginService                          │
│  - Discovery (find agents by capability)                    │
│  - Instantiation (create agent instances)                   │
│  - Execution Tracking (analytics)                           │
└──────────────────────────────────┬──────────────────────────┘
                                   │
┌──────────────────────────────────▼──────────────────────────┐
│                   WorkflowEngine                             │
│  - Checks for custom agents first                           │
│  - Falls back to built-in executors                         │
│  - Uses AgentPluginExecutor wrapper                         │
└──────────────────────────────────┬──────────────────────────┘
                                   │
┌──────────────────────────────────▼──────────────────────────┐
│                Database Models                               │
│  - AgentPlugin (main model)                                  │
│  - AgentCapability (what it can do)                          │
│  - AgentTool (what tools it uses)                            │
│  - AgentTemplateBinding (workflow bindings)                  │
│  - AgentPluginExecution (tracking)                           │
└──────────────────────────────────────────────────────────────┘
```

---

## 📋 Database Schema

### AgentPlugin
```ruby
{
  name: "Sales Email Generator",
  slug: "sales_email_generator",
  role: "executor",                    # executor, planner, analyst, verifier
  description: "Generates personalized sales emails...",
  version: "1.0.0",
  status: "active",                    # draft, active, deprecated
  agent_class: "Agents::Specialized::ExecutorAgent",
  priority: 80,                         # 0-100, higher = preferred
  entity_id: null,                     # nil = system-wide
  configuration: {},                    # Custom JSON config
  system_prompt: {},                   # AI prompt
  capabilities_definition: {}          # Metadata
}
```

### AgentCapability
```ruby
{
  agent_plugin_id: 1,
  capability_name: "email_generation",
  contract_schema: {
    inputs: [
      { name: "lead_name", type: "string", required: true }
    ],
    outputs: [
      { name: "email_subject", type: "string" }
    ]
  },
  implementation_notes: "Uses GPT-4 for generation"
}
```

### AgentTool
```ruby
{
  agent_plugin_id: 1,
  tool_name: "create_object",
  required: true                       # Must be available
}
```

---

## 🚀 Quick Start

### 1. Access the Admin UI

Navigate to: `/admin/agent_plugins`

### 2. Create Your First Agent

**Example: Social Media Post Generator**

```yaml
Name: LinkedIn Post Generator
Role: executor
Description: Creates engaging LinkedIn posts with hashtags
Priority: 75
Status: active

Capabilities:
  - name: post_generation
    contract:
      inputs:
        - topic (string)
        - tone (string)
      outputs:
        - post_content (string)
        - hashtags (array)

Required Tools:
  - create_object

System Prompt:
  "You are a LinkedIn content expert. Create engaging posts
   that drive interaction. Include 3-5 relevant hashtags."

Configuration:
  {
    "max_length": 1300,
    "include_emojis": false,
    "target_engagement": "professional"
  }
```

### 3. Test the Agent

1. Click "Test" on the agent detail page
2. Provide test input:
   ```json
   {
     "topic": "AI in Marketing",
     "tone": "informative"
   }
   ```
3. View the generated output
4. Activate if satisfied

---

## 🔧 Usage Examples

### From Code

```ruby
# Discover agents
service = AgentPluginService.new(entity: current_entity, user: current_user)
agent_plugin = service.discover_agent(capabilities: ['email_generation'])

# Instantiate and use
agent_instance = service.instantiate_agent(agent_plugin, context)
result = agent_instance.achieve_goal("Write a sales email", context)

# Track execution
execution = service.create_execution_record(agent_plugin, context)
service.complete_execution(execution, result)
```

### In Workflows

Agents are **automatically discovered** during workflow execution:

```yaml
# workflow_template.yml
phases:
  - id: execute_goal
    type: execute_goal
    goal: "Generate sales email"
    # If an agent_plugin exists with 'email_generation' capability
    # it will be used automatically!
```

### Explicit Binding

Bind specific agents to workflows:

```ruby
AgentTemplateBinding.create!(
  workflow_template: template,
  agent_plugin: sales_agent,
  phase: "execute_goal",
  required: true,
  execution_order: 1
)
```

---

## 📊 Analytics & Monitoring

### Performance Metrics

Access: `/admin/agent_plugins/:id` or `/admin/agent_plugins/analytics`

**Available Metrics:**
- Total executions
- Success rate
- Average duration (ms)
- Total tokens used
- Execution timeline (chart)
- Error rates

### Example Analytics Query

```ruby
# Get top performing agents
AgentPlugin.active.map do |agent|
  stats = agent.execution_stats(since: 30.days.ago)
  {
    name: agent.name,
    executions: stats[:total_executions],
    success_rate: stats[:success_rate],
    avg_duration: stats[:avg_duration_ms]
  }
end.sort_by { |s| -s[:success_rate] }
```

---

## 🧪 Testing Agents

### Via Admin UI

1. Navigate to `/admin/agent_plugins/:id/test`
2. Select test method:
   - **Execute Goal**: Provide a goal statement
   - **Run Prompt**: Provide a raw AI prompt
3. Add context (JSON)
4. Click "Run Test"
5. View results and execution time

### Via Rails Console

```ruby
# Load agent
agent = AgentPlugin.find_by(slug: 'sales_email_generator')

# Create service
service = AgentPluginService.new(entity: Entity.first, user: User.first)

# Instantiate
instance = service.instantiate_agent(agent, {
  lead_name: "John Smith",
  company_name: "Acme Corp"
})

# Test execution
result = instance.achieve_goal("Generate sales email", context)
```

---

## 🔄 Cloning Agents

Create variations of existing agents:

```ruby
# Via UI: Click "Clone" button on agent detail page

# Via Code:
service = AgentPluginService.new(entity: current_entity)
cloned = service.clone_agent(
  source_agent,
  new_name: "Sales Email Generator V2",
  entity: my_entity
)

# Modify the cloned agent
cloned.update!(
  priority: 90,
  configuration: { max_length: 200 }
)
```

**Use Cases:**
- A/B testing agent variations
- Entity-specific customizations
- Version control for agents
- Experimentation

---

## 🎨 Advanced Features

### 1. Capability Contracts

Enforce input/output schemas:

```ruby
# In AgentCapability
contract_schema: {
  inputs: [
    {
      name: "user_data",
      type: "object",
      required: true,
      schema: {
        name: "string",
        email: "string",
        company: "string"
      }
    }
  ],
  outputs: [
    {
      name: "generated_content",
      type: "string",
      min_length: 50,
      max_length: 500
    }
  ]
}
```

### 2. Multi-Entity Agents

```ruby
# System-wide agent (entity_id = nil)
# Available to all entities
AgentPlugin.create!(entity_id: nil, ...)

# Entity-specific agent
# Only for specific entity
AgentPlugin.create!(entity: my_entity, ...)
```

### 3. Priority-Based Selection

When multiple agents match criteria:

```ruby
# Higher priority agents are selected first
sales_agent_v1.update!(priority: 70)
sales_agent_v2.update!(priority: 90)  # This one gets selected
```

---

## 🐛 Troubleshooting

### Agent Not Being Used

**Check:**
1. Status is "active"
2. Required tools are available
3. Capabilities match phase requirements
4. Priority is higher than alternatives

**Debug:**
```ruby
service = AgentPluginService.new(entity: entity)
agent = service.find_agent_for_phase('execute_goal')
puts "Selected agent: #{agent&.name || 'None'}"
```

### Execution Failures

**Check Logs:**
```ruby
execution = AgentPluginExecution.last
puts execution.output_result['error']
puts execution.agent_plugin.required_tools
```

**Validate Agent:**
```ruby
service = AgentPluginService.new
validation = service.validate_agent(agent_plugin)
puts validation[:errors]
```

---

## 📈 Best Practices

### 1. Naming Conventions
- **Name:** Human-readable, descriptive
- **Slug:** Snake_case, unique, stable
- **Version:** Semantic versioning (X.Y.Z)

### 2. Capability Contracts
- Define clear input/output schemas
- Use required: true for mandatory fields
- Document expected data types

### 3. Tool Dependencies
- Mark critical tools as required: true
- List optional tools for enhanced functionality
- Test tool availability before activation

### 4. Testing
- Always test before activating
- Use realistic test data
- Verify output format matches contract

### 5. Monitoring
- Review execution stats weekly
- Set up alerts for high failure rates
- Track token usage for cost management

---

## 🔐 Security Considerations

### Access Control
- Only admins can create/edit agents
- All executions are logged and tracked
- Agent activities are audited

### Data Privacy
- Agent context is sanitized before storage
- Sensitive fields are excluded from logs
- Entity isolation is enforced

### Validation
- Tool names are validated against ToolCatalog
- Agent classes must exist
- Contract schemas are validated on save

---

## 🚦 Migration Path

### Existing System
Your existing built-in executors continue to work:
- `Agents::GatherContextExecutor`
- `Agents::GoalExecutor`
- `Agents::ValidationExecutor`

### Hybrid Approach
The system checks for custom agents **first**, then falls back to built-ins.

### Full Migration
1. Create agent plugin for each built-in executor
2. Bind to relevant templates
3. Test thoroughly
4. Activate
5. (Optional) Deprecate built-ins

---

## 📚 API Reference

### AgentPluginService

```ruby
service = AgentPluginService.new(entity:, user:)

# Discovery
service.discover_agents(capabilities: [], role: nil)
service.discover_agent(capabilities: [], role: nil)
service.find_agent_for_phase(phase, template: nil)

# Instantiation
service.instantiate_agent(agent_plugin, context)
service.instantiate_agent_for_phase(phase, template:, context:)

# Tracking
service.create_execution_record(agent_plugin, context)
service.complete_execution(execution, output)
service.fail_execution(execution, error_message)

# Validation
service.validate_agent(agent_plugin)
service.validate_required_tools!(agent_plugin)

# Utilities
service.clone_agent(source_agent, new_name:, entity:)
service.agent_exists?(slug)
service.get_agent(slug)
```

---

## 🎓 Examples

See `/db/seeds/agent_plugins.rb` for complete examples including:
- Sales Email Generator
- Content Quality Analyzer
- Campaign Optimizer
- AI Landing Page Creator
- Customer Journey Mapper

---

## 🔮 Future Enhancements

- [ ] Agent marketplace/library
- [ ] Visual workflow builder with drag-drop agents
- [ ] A/B testing framework
- [ ] Agent composition (agent teams)
- [ ] Version management with rollback
- [ ] Performance optimization recommendations
- [ ] Multi-language support for prompts
- [ ] Agent inheritance/mixins

---

## 📞 Support

**Issues:** Report bugs in GitHub Issues
**Questions:** See docs or ask in #agent-framework channel
**Contributions:** PRs welcome!

---

Built with ❤️ using Claude Code
