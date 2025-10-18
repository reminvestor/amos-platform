# Scout AI Tool Development Guide

Complete guide for creating and testing Scout AI tools.

## Tool Anatomy

Every tool extends `BaseTool` and has two main parts:

### 1. Definition (What AI Sees)

```ruby
def self.definition
  {
    name: 'tool_name',  # Unique identifier
    description: 'Clear description of what this tool does',
    category: 'optional_category',
    input_schema: {
      type: 'object',
      properties: {
        param_name: {
          type: 'string',  # string, integer, boolean, array, object
          description: 'What this parameter does'
        }
      },
      required: ['param_name']  # List of required parameters
    }
  }
end
```

### 2. Execute Method (What Tool Does)

```ruby
def execute(args)
  # Available instance variables:
  # @user - Current user
  # @entity - Current entity (tenant)
  # @workflow_execution - Current workflow execution

  # Extract arguments
  param_value = args['param_name']

  # Do work
  result = do_something(param_value)

  # Return response
  success_response(
    message: "Success message",
    data: { key: value }
  )
rescue => e
  error_response("Error: #{e.message}")
end
```

## Step-by-Step Tool Creation

### 1. Create Tool File

```bash
# File: app/services/tools/your_tool_name_tool.rb
touch app/services/tools/send_email_tool.rb
```

### 2. Define Class Structure

```ruby
module Tools
  class SendEmailTool < BaseTool
    def self.definition
      {
        name: 'send_email',
        description: 'Send an email to specified recipients',
        category: 'communication',
        input_schema: {
          type: 'object',
          properties: {
            recipients: {
              type: 'array',
              description: 'Email addresses to send to',
              items: { type: 'string' }
            },
            subject: {
              type: 'string',
              description: 'Email subject line'
            },
            body: {
              type: 'string',
              description: 'Email body content'
            }
          },
          required: ['recipients', 'subject', 'body']
        }
      }
    end

    def execute(args)
      recipients = args['recipients']
      subject = args['subject']
      body = args['body']

      # Validate
      return error_response('No recipients') if recipients.empty?

      # Send email
      EmailService.send(
        to: recipients,
        subject: subject,
        body: body,
        from: @entity.email_address
      )

      success_response(
        message: "Email sent to #{recipients.size} recipient(s)",
        data: { recipients: recipients }
      )
    rescue => e
      error_response("Failed to send email: #{e.message}")
    end
  end
end
```

### 3. Test the Tool

```ruby
# File: test/services/tools/send_email_tool_test.rb
require 'test_helper'

class SendEmailToolTest < ActiveSupport::TestCase
  def setup
    @entity = entities(:one)
    @user = users(:one)
    @tool = Tools::SendEmailTool.new(
      entity: @entity,
      user: @user
    )
  end

  test 'sends email successfully' do
    result = @tool.execute({
      'recipients' => ['test@example.com'],
      'subject' => 'Test',
      'body' => 'Hello'
    })

    assert result[:success]
    assert_includes result[:message], 'sent'
  end

  test 'fails with no recipients' do
    result = @tool.execute({
      'recipients' => [],
      'subject' => 'Test',
      'body' => 'Hello'
    })

    assert_not result[:success]
    assert_includes result[:message], 'No recipients'
  end
end
```

### 4. Verify Auto-Discovery

```bash
# Tool should be automatically registered
docker-compose run --rm web rails runner "
  require 'tools/tool_catalog'
  catalog = Tools::ToolCatalog.instance
  puts catalog.all_tools.keys.include?('send_email')
"
# Should output: true
```

## Tool Patterns

### Data Retrieval Tool

```ruby
class GetCampaignsTool < BaseTool
  def self.definition
    {
      name: 'get_campaigns',
      description: 'Retrieve list of campaigns',
      input_schema: {
        type: 'object',
        properties: {
          status: {
            type: 'string',
            description: 'Filter by status',
            enum: ['draft', 'active', 'paused', 'completed']
          },
          limit: {
            type: 'integer',
            description: 'Maximum number of results'
          }
        }
      }
    }
  end

  def execute(args)
    campaigns = Campaign.accessible_by(@user)
    campaigns = campaigns.where(status: args['status']) if args['status']
    campaigns = campaigns.limit(args['limit'] || 10)

    success_response(
      message: "Found #{campaigns.count} campaign(s)",
      data: {
        campaigns: campaigns.map do |c|
          { id: c.id, name: c.name, status: c.status }
        end
      }
    )
  end
end
```

### Creation Tool

```ruby
class CreateCampaignTool < BaseTool
  def self.definition
    {
      name: 'create_campaign',
      description: 'Create a new email campaign',
      input_schema: {
        type: 'object',
        properties: {
          name: { type: 'string', description: 'Campaign name' },
          subject: { type: 'string', description: 'Email subject' }
        },
        required: ['name', 'subject']
      }
    }
  end

  def execute(args)
    campaign = Campaign.create!(
      entity: @entity,
      name: args['name'],
      subject: args['subject'],
      status: 'draft'
    )

    success_response(
      message: "Campaign '#{campaign.name}' created",
      data: { id: campaign.id, name: campaign.name }
    )
  rescue ActiveRecord::RecordInvalid => e
    error_response("Validation failed: #{e.message}")
  end
end
```

### Update Tool

```ruby
class UpdateCampaignTool < BaseTool
  def self.definition
    {
      name: 'update_campaign',
      description: 'Update existing campaign',
      input_schema: {
        type: 'object',
        properties: {
          campaign_id: { type: 'integer', description: 'Campaign ID' },
          name: { type: 'string', description: 'New name' },
          status: { type: 'string', description: 'New status' }
        },
        required: ['campaign_id']
      }
    }
  end

  def execute(args)
    campaign = Campaign.accessible_by(@user).find(args['campaign_id'])

    updates = {}
    updates[:name] = args['name'] if args['name']
    updates[:status] = args['status'] if args['status']

    campaign.update!(updates)

    success_response(
      message: "Campaign updated",
      data: { id: campaign.id, **updates }
    )
  rescue ActiveRecord::RecordNotFound
    error_response("Campaign not found")
  end
end
```

### Delegation Tool

```ruby
class DelegateTaskTool < BaseTool
  def self.definition
    {
      name: 'delegate_task',
      description: 'Delegate complex task to another workflow',
      input_schema: {
        type: 'object',
        properties: {
          task_type: { type: 'string', description: 'Type of task' },
          params: { type: 'object', description: 'Task parameters' }
        },
        required: ['task_type']
      }
    }
  end

  def execute(args)
    # Invoke another workflow or tool
    result = Tools::DelegateToPlannerTool.new(
      user: @user,
      entity: @entity,
      workflow_execution: @workflow_execution
    ).execute({
      'user_message' => args['task_type'],
      'context' => args['params']
    })

    success_response(
      message: "Task delegated",
      data: result[:data]
    )
  end
end
```

## Best Practices

### Clear Descriptions
```ruby
# Bad
description: 'Does stuff with campaigns'

# Good
description: 'Creates a new email campaign with draft status and returns campaign ID'
```

### Specific Parameter Types
```ruby
# Bad
properties: {
  status: { type: 'string', description: 'Status' }
}

# Good
properties: {
  status: {
    type: 'string',
    description: 'Campaign status',
    enum: ['draft', 'active', 'paused', 'completed']
  }
}
```

### Error Handling
```ruby
def execute(args)
  # Specific error messages
  return error_response('Campaign ID required') unless args['id']

  # Catch specific exceptions
  campaign = Campaign.find(args['id'])
rescue ActiveRecord::RecordNotFound
  error_response('Campaign not found')
rescue ActiveRecord::RecordInvalid => e
  error_response("Validation failed: #{e.record.errors.full_messages.join(', ')}")
rescue => e
  error_response("Unexpected error: #{e.message}")
end
```

### Entity Scoping
```ruby
# Always scope to entity
campaigns = Campaign.accessible_by(@user)

# Never query globally
campaigns = Campaign.all  # BAD - crosses entity boundaries
```

### Return Useful Data
```ruby
# Bad
success_response(message: "Done")

# Good
success_response(
  message: "Campaign created successfully",
  data: {
    id: campaign.id,
    name: campaign.name,
    url: campaign_url(campaign)
  }
)
```

## Testing Strategies

### Unit Tests
```ruby
test 'validates required parameters' do
  result = @tool.execute({})
  assert_not result[:success]
end

test 'respects entity scoping' do
  other_entity_campaign = campaigns(:other_entity)
  result = @tool.execute({ 'id' => other_entity_campaign.id })
  assert_not result[:success]
  assert_includes result[:message], 'not found'
end
```

### Integration Tests
```ruby
test 'works in workflow context' do
  execution = WorkflowExecution.create!(
    entity: @entity,
    user: @user,
    template_name: 'test'
  )

  tool = Tools::CreateCampaignTool.new(
    entity: @entity,
    user: @user,
    workflow_execution: execution
  )

  result = tool.execute({ 'name' => 'Test' })
  assert result[:success]

  # Verify workflow context updated
  assert_not_nil execution.reload.metadata['last_campaign_id']
end
```

## Debugging Tools

### Rails Console
```ruby
# Load tool
require 'tools/tool_catalog'
catalog = Tools::ToolCatalog.instance
tool_class = catalog.get_tool('send_email')

# Instantiate
tool = tool_class.new(
  entity: Entity.first,
  user: User.first
)

# Test execute
result = tool.execute({
  'recipients' => ['test@example.com'],
  'subject' => 'Test',
  'body' => 'Hello'
})

puts result.inspect
```

### Logging
```ruby
def execute(args)
  Rails.logger.info "SendEmailTool: Sending to #{args['recipients']}"

  # ... do work

  Rails.logger.info "SendEmailTool: Success!"
end
```

## Common Issues

**Tool not appearing in catalog:**
- File must be in `app/services/tools/`
- Must extend `BaseTool`
- Must have `definition` class method
- Restart Rails console

**Parameters not being passed:**
- Check `input_schema` matches what you expect
- Check AI is providing parameters in correct format
- Log `args` at start of `execute` method

**Entity scoping issues:**
- Always use `@entity` and `@user`
- Use `.accessible_by(@user)` scope
- Never query `Model.all` directly

**Response format errors:**
- Always return `success_response()` or `error_response()`
- Don't return plain hashes or strings
- Don't raise exceptions (catch and return error_response)

## Resources

- [BaseTool Source](../../../app/services/tools/base_tool.rb)
- [ToolCatalog Source](../../../app/services/tools/tool_catalog.rb)
- [Existing Tools](../../../app/services/tools/) - Learn from examples
- [Tool Testing Skill](../../testing-tools-manually/SKILL.md)
