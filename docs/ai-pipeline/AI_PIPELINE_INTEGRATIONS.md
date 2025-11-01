# AI Pipeline - Integration Architecture Guide

**Last Updated**: January 29, 2025

This guide shows how to add support for **new ticket systems** and **AI model providers** to the AI Pipeline.

---

## 📋 Part 1: Ticket System Integration

Ticket systems are where work items come from (JIRA, Azure DevOps, GitHub Issues, etc.).

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  TicketWatcherJob (Universal)                               │
│  - Polls all active ticket connections every 5 minutes      │
│  - Calls connection.client.fetch_recent_tickets()           │
│  - Applies filtering rules                                  │
│  - Creates PipelineExecution for matching tickets           │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  MCP Connection (stores credentials per system)             │
│  - system_type: 'jira', 'azure_devops', 'github', etc.     │
│  - config: { encrypted credentials }                        │
│  - metadata: { pipeline_filters }                           │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Client Adapter (system-specific)                           │
│  - MCP::JiraClient                                          │
│  - MCP::AzureDevOpsClient                                   │
│  - MCP::GithubIssuesClient  ← YOU ADD THIS                 │
│  - MCP::LinearClient         ← YOU ADD THIS                 │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  External System API                                        │
│  - JIRA Cloud REST API                                      │
│  - Azure DevOps REST API                                    │
│  - GitHub GraphQL API                                       │
│  - Linear GraphQL API                                       │
└─────────────────────────────────────────────────────────────┘
```

### Required Interface

Every ticket system client must implement this interface:

```ruby
module MCP
  class YourSystemClient
    # Required method - fetch tickets created/updated since a given time
    def fetch_recent_tickets(since:)
      # Return array of tickets in STANDARD FORMAT (see below)
    end

    # Optional - post a comment to a ticket
    def post_comment(ticket_id, comment)
      # Post clarification questions or status updates
    end

    # Optional - update ticket status
    def transition_ticket(ticket_id, new_status)
      # Move ticket to "In Progress" when pipeline starts
    end
  end
end
```

### Standard Ticket Format

All clients must return tickets in this format:

```ruby
{
  # Required fields
  id: "PROJ-123",                    # Unique ticket ID
  title: "Add user authentication",  # Ticket title
  description: "Full description",   # Ticket body/description
  url: "https://...",                # Link to ticket
  status: "Ready for Dev",           # Current status/state

  # Filtering fields
  labels: ["backend", "urgent"],     # Array of labels/tags
  issue_type: "Story",               # Type: Story, Task, Bug, etc.
  assignee: "username",              # Assigned user (or nil)
  priority: "high",                  # Priority level

  # Optional fields
  components: ["Backend", "API"],    # Components/areas
  custom_fields: {                   # Custom field values
    "Story Points" => 5,
    "Ready for AI" => true
  },
  metadata: {                        # Any extra data
    created_at: "2025-01-29T10:00:00Z",
    reporter: "user@example.com"
  }
}
```

---

## 🎯 Example 1: GitHub Issues Integration

Let's add full support for GitHub Issues as a ticket system.

### Step 1: Create Client

```ruby
# app/services/mcp/github_issues_client.rb
module MCP
  class GithubIssuesClient
    def initialize(connection)
      @connection = connection
      @config = connection.config
      @github = Git::GithubClient.new(connection)
    end

    def fetch_recent_tickets(since:)
      # Fetch issues from GitHub
      issues = fetch_issues_since(since)

      # Convert to standard format
      issues.map { |issue| normalize_issue(issue) }
    end

    def post_comment(ticket_id, comment)
      @github.add_comment(
        @config[:repository],
        ticket_id.to_i,
        comment
      )
    end

    def transition_ticket(ticket_id, new_status)
      # GitHub doesn't have workflow states, use labels instead
      case new_status
      when 'in_progress'
        add_label(ticket_id, 'in-progress')
      when 'done'
        close_issue(ticket_id)
      end
    end

    private

    def fetch_issues_since(since)
      # Use GitHub MCP tools or direct API
      result = @github.call_mcp_tool('search_issues', {
        query: "repo:#{@config[:repository]} is:issue is:open updated:>=#{since.iso8601}",
        sort: 'updated',
        order: 'desc'
      })

      result[:content] || []
    end

    def normalize_issue(issue)
      {
        # Required fields
        id: issue['number'].to_s,
        title: issue['title'],
        description: issue['body'] || '',
        url: issue['html_url'],
        status: issue['state'],  # 'open' or 'closed'

        # Filtering fields
        labels: issue['labels'].map { |l| l['name'] },
        issue_type: infer_type_from_labels(issue['labels']),
        assignee: issue['assignee']&.dig('login'),
        priority: infer_priority_from_labels(issue['labels']),

        # Optional fields
        components: [],  # GitHub doesn't have components
        custom_fields: {},
        metadata: {
          created_at: issue['created_at'],
          updated_at: issue['updated_at'],
          author: issue['user']['login'],
          milestone: issue['milestone']&.dig('title'),
          reactions: issue['reactions']
        }
      }
    end

    def infer_type_from_labels(labels)
      label_names = labels.map { |l| l['name'].downcase }

      return 'Bug' if label_names.any? { |l| l.include?('bug') }
      return 'Feature' if label_names.any? { |l| l.include?('feature') || l.include?('enhancement') }
      return 'Task' if label_names.any? { |l| l.include?('task') }

      'Issue'  # Default type
    end

    def infer_priority_from_labels(labels)
      label_names = labels.map { |l| l['name'].downcase }

      return 'critical' if label_names.any? { |l| l.include?('critical') || l.include?('urgent') }
      return 'high' if label_names.any? { |l| l.include?('high') || l.include?('priority') }

      'medium'
    end

    def add_label(issue_number, label)
      @github.call_mcp_tool('add_labels', {
        owner: @config[:organization],
        repo: @config[:repository].split('/').last,
        issue_number: issue_number.to_i,
        labels: [label]
      })
    end

    def close_issue(issue_number)
      @github.call_mcp_tool('update_issue', {
        owner: @config[:organization],
        repo: @config[:repository].split('/').last,
        issue_number: issue_number.to_i,
        state: 'closed'
      })
    end
  end
end
```

### Step 2: Register System Type

```ruby
# app/models/mcp_connection.rb (add to enum)
enum :system_type, {
  jira: 0,
  azure_devops: 1,
  github: 2,
  azure_repos: 3,
  github_issues: 4  # ← Add this
}
```

### Step 3: Add Client Factory Method

```ruby
# app/models/mcp_connection.rb
def client
  case system_type.to_sym
  when :jira
    MCP::JiraClient.new(self)
  when :azure_devops
    MCP::AzureDevOpsClient.new(self)
  when :github_issues
    MCP::GithubIssuesClient.new(self)  # ← Add this
  when :github, :azure_repos
    Git::GithubClient.new(self)  # For git operations only
  else
    raise "Unknown system type: #{system_type}"
  end
end

def ticket_systems
  where(system_type: [:jira, :azure_devops, :github_issues])  # ← Add here
end
```

### Step 4: Configure Connection

```ruby
# In Rails console or seed file
entity = Entity.find_by(name: 'Demo Company')

github_issues_connection = McpConnection.create!(
  entity: entity,
  system_type: :github_issues,
  name: 'GitHub Issues - agent_marketing',
  config: {
    organization: 'NuvolaNetworks',
    repository: 'NuvolaNetworks/agent_marketing',
    token: ENV['GITHUB_API_TOKEN']
  },
  metadata: {
    pipeline_filters: {
      # Only open issues
      allowed_statuses: ['open'],

      # Must have ai-dev label
      require_label: 'ai-dev',

      # Only features and bugs
      allowed_issue_types: ['Feature', 'Bug', 'Task'],

      # Exclude wontfix, duplicate
      exclude_labels: ['wontfix', 'duplicate', 'blocked'],

      # Only unassigned
      assignee_filter: 'unassigned'
    }
  },
  status: :active
)
```

### Step 5: Test It

```ruby
# Fetch recent issues
client = github_issues_connection.client
issues = client.fetch_recent_tickets(since: 1.day.ago)

# Check format
issues.each do |issue|
  puts "✅ #{issue[:id]}: #{issue[:title]}"
  puts "   Type: #{issue[:issue_type]}, Status: #{issue[:status]}"
  puts "   Labels: #{issue[:labels].join(', ')}"
end

# Test filtering
job = TicketWatcherJob.new
issues.each do |issue|
  ready = job.send(:ticket_ready_for_pipeline?, issue, github_issues_connection)
  puts "#{ready ? '✅' : '❌'} Would process: #{issue[:id]}"
end
```

---

## 🎯 Example 2: Linear Integration

Linear is a popular modern project management tool. Here's how to integrate it:

### Step 1: Create Client

```ruby
# app/services/mcp/linear_client.rb
require 'graphql/client'
require 'graphql/client/http'

module MCP
  class LinearClient
    GRAPHQL_ENDPOINT = 'https://api.linear.app/graphql'

    def initialize(connection)
      @config = connection.config
      @http = GraphQL::Client::HTTP.new(GRAPHQL_ENDPOINT) do
        def headers(context)
          { 'Authorization' => context[:api_key] }
        end
      end
      @client = GraphQL::Client.new(schema: schema, execute: @http)
    end

    def fetch_recent_tickets(since:)
      query = @client.parse <<~GRAPHQL
        query($after: DateTime!) {
          issues(
            filter: { updatedAt: { gte: $after } }
            orderBy: updatedAt
          ) {
            nodes {
              id
              identifier
              title
              description
              url
              state { name }
              labels { nodes { name } }
              assignee { name email }
              priority
              createdAt
              updatedAt
            }
          }
        }
      GRAPHQL

      result = @client.query(
        query,
        variables: { after: since.iso8601 },
        context: { api_key: @config[:api_key] }
      )

      result.data.issues.nodes.map { |issue| normalize_issue(issue) }
    end

    def post_comment(ticket_id, comment)
      mutation = @client.parse <<~GRAPHQL
        mutation($issueId: String!, $body: String!) {
          commentCreate(input: { issueId: $issueId, body: $body }) {
            success
          }
        }
      GRAPHQL

      @client.query(mutation, variables: {
        issueId: ticket_id,
        body: comment
      }, context: { api_key: @config[:api_key] })
    end

    private

    def normalize_issue(issue)
      {
        id: issue.identifier,  # e.g., "ENG-123"
        title: issue.title,
        description: issue.description || '',
        url: issue.url,
        status: issue.state.name,
        labels: issue.labels.nodes.map(&:name),
        issue_type: infer_type(issue),
        assignee: issue.assignee&.email,
        priority: map_priority(issue.priority),
        components: [],
        custom_fields: {},
        metadata: {
          created_at: issue.created_at,
          updated_at: issue.updated_at
        }
      }
    end

    def infer_type(issue)
      # Linear doesn't have explicit types, infer from labels or priority
      labels = issue.labels.nodes.map(&:name).map(&:downcase)

      return 'Bug' if labels.include?('bug')
      return 'Feature' if labels.include?('feature')

      'Task'
    end

    def map_priority(linear_priority)
      # Linear uses 0-4 (0=No priority, 4=Urgent)
      case linear_priority
      when 4 then 'critical'
      when 3 then 'high'
      when 2 then 'medium'
      when 1 then 'low'
      else 'medium'
      end
    end

    def schema
      # Load GraphQL schema (cache this in production)
      GraphQL::Client.load_schema(@http)
    end
  end
end
```

### Step 2: Add Gem Dependencies

```ruby
# Gemfile
gem 'graphql-client'  # For Linear GraphQL API
```

### Step 3: Configure

```ruby
linear_connection = McpConnection.create!(
  entity: entity,
  system_type: :linear,
  name: 'Linear - Engineering Team',
  config: {
    api_key: ENV['LINEAR_API_KEY'],
    team_id: 'your-team-id'
  },
  metadata: {
    pipeline_filters: {
      allowed_statuses: ['Todo', 'Ready'],  # Linear state names
      allowed_issue_types: ['Task', 'Feature'],
      exclude_labels: ['blocked', 'spike'],
      assignee_filter: 'unassigned'
    }
  }
)
```

---

## 🤖 Part 2: AI Model Integration

AI models generate the code. Currently uses AWS Bedrock (Claude), but you can swap in other providers.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Agent (e.g., CoderAgent)                                   │
│  - Prepares prompt with context                             │
│  - Calls call_claude() method from BaseAgent                │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  BedrockService (AI Provider Abstraction)                   │
│  - send_message() / converse_with_streaming()               │
│  - Routes to appropriate provider based on model name       │
│  - Tracks token usage and costs                             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Provider Client                                             │
│  - AWS Bedrock Client (current)                             │
│  - OpenAI Client          ← YOU ADD THIS                    │
│  - Google Gemini Client   ← YOU ADD THIS                    │
│  - Azure OpenAI Client    ← YOU ADD THIS                    │
└─────────────────────────────────────────────────────────────┘
```

### Required Interface

Every AI provider must implement:

```ruby
class AiProvider
  # Generate completion with streaming
  def generate(prompt, options = {})
    # Returns: { content: "...", usage: { input_tokens: 100, output_tokens: 200 } }
  end

  # Tool calling support (optional but recommended)
  def generate_with_tools(prompt, tools, options = {})
    # Returns: { content: "...", tool_calls: [...], usage: {...} }
  end
end
```

---

## 🎯 Example 3: OpenAI Integration

Add GPT-4 as an alternative to Claude for code generation.

### Step 1: Create OpenAI Provider

```ruby
# app/services/ai_providers/openai_provider.rb
module AiProviders
  class OpenaiProvider
    def initialize(api_key: ENV['OPENAI_API_KEY'])
      require 'openai'
      @client = OpenAI::Client.new(access_token: api_key)
    end

    def generate(prompt, options = {})
      model = options[:model] || 'gpt-4-turbo-preview'
      temperature = options[:temperature] || 0.7
      max_tokens = options[:max_tokens] || 4000

      response = @client.chat(
        parameters: {
          model: model,
          messages: build_messages(prompt, options[:system_prompt]),
          temperature: temperature,
          max_tokens: max_tokens
        }
      )

      {
        content: response.dig('choices', 0, 'message', 'content'),
        usage: {
          input_tokens: response.dig('usage', 'prompt_tokens'),
          output_tokens: response.dig('usage', 'completion_tokens')
        },
        model: model
      }
    end

    def generate_with_tools(prompt, tools, options = {})
      model = options[:model] || 'gpt-4-turbo-preview'

      response = @client.chat(
        parameters: {
          model: model,
          messages: build_messages(prompt, options[:system_prompt]),
          tools: format_tools_for_openai(tools),
          temperature: options[:temperature] || 0.7,
          max_tokens: options[:max_tokens] || 4000
        }
      )

      message = response.dig('choices', 0, 'message')

      {
        content: message['content'],
        tool_calls: parse_tool_calls(message['tool_calls']),
        usage: {
          input_tokens: response.dig('usage', 'prompt_tokens'),
          output_tokens: response.dig('usage', 'completion_tokens')
        },
        model: model
      }
    end

    def calculate_cost(model, usage)
      input_tokens = usage[:input_tokens] || 0
      output_tokens = usage[:output_tokens] || 0

      case model
      when 'gpt-4-turbo-preview', 'gpt-4-turbo'
        # $10/$30 per 1M tokens
        (input_tokens / 1_000_000.0 * 10.0) + (output_tokens / 1_000_000.0 * 30.0)
      when 'gpt-4'
        # $30/$60 per 1M tokens
        (input_tokens / 1_000_000.0 * 30.0) + (output_tokens / 1_000_000.0 * 60.0)
      when 'gpt-3.5-turbo'
        # $0.50/$1.50 per 1M tokens
        (input_tokens / 1_000_000.0 * 0.50) + (output_tokens / 1_000_000.0 * 1.50)
      else
        0.0
      end
    end

    private

    def build_messages(user_prompt, system_prompt)
      messages = []
      messages << { role: 'system', content: system_prompt } if system_prompt
      messages << { role: 'user', content: user_prompt }
      messages
    end

    def format_tools_for_openai(tools)
      tools.map do |tool|
        {
          type: 'function',
          function: {
            name: tool[:name],
            description: tool[:description],
            parameters: tool[:input_schema] || tool[:parameters]
          }
        }
      end
    end

    def parse_tool_calls(tool_calls)
      return [] unless tool_calls

      tool_calls.map do |call|
        {
          id: call['id'],
          name: call['function']['name'],
          arguments: JSON.parse(call['function']['arguments'])
        }
      end
    end
  end
end
```

### Step 2: Update BedrockService

```ruby
# app/services/bedrock_service.rb
class BedrockService
  def initialize(entity: nil, provider: :bedrock)
    @entity = entity
    @provider = select_provider(provider)
  end

  def send_message(system_prompt, messages, model: 'claude-sonnet-4-5', **options)
    # Route to appropriate provider based on model
    if model.start_with?('gpt-')
      send_to_openai(system_prompt, messages, model: model, **options)
    elsif model.start_with?('gemini-')
      send_to_gemini(system_prompt, messages, model: model, **options)
    else
      send_to_bedrock(system_prompt, messages, model: model, **options)
    end
  end

  private

  def select_provider(provider_name)
    case provider_name
    when :openai
      AiProviders::OpenaiProvider.new
    when :gemini
      AiProviders::GeminiProvider.new
    when :bedrock
      # Existing Bedrock client
      self
    else
      raise "Unknown provider: #{provider_name}"
    end
  end

  def send_to_openai(system_prompt, messages, model:, **options)
    openai = AiProviders::OpenaiProvider.new

    # Extract user message
    user_message = messages.last[:content]

    result = openai.generate(
      user_message,
      system_prompt: system_prompt,
      model: model,
      temperature: options[:temperature] || 0.7,
      max_tokens: options[:max_tokens] || 4000
    )

    {
      success: true,
      content: result[:content],
      usage: result[:usage],
      model_used: model
    }
  rescue => e
    {
      success: false,
      error: e.message
    }
  end

  def send_to_bedrock(system_prompt, messages, model:, **options)
    # Existing Bedrock implementation
    # ... (your current code)
  end
end
```

### Step 3: Configure Agent to Use OpenAI

```ruby
# app/services/agents/coder_agent.rb
class CoderAgent < BaseAgent
  def model
    # Use GPT-4 instead of Claude
    ENV['CODER_MODEL'] || 'gpt-4-turbo-preview'

    # Or keep Claude:
    # 'claude-sonnet-4-5-20250929'
  end

  # Cost calculation needs to know the provider
  def calculate_cost(usage)
    if model.start_with?('gpt-')
      openai_provider.calculate_cost(model, usage)
    else
      super  # Use BaseAgent's Claude pricing
    end
  end

  private

  def openai_provider
    @openai_provider ||= AiProviders::OpenaiProvider.new
  end
end
```

### Step 4: Add Environment Variable

```bash
# .env
OPENAI_API_KEY=sk-...
CODER_MODEL=gpt-4-turbo-preview  # or claude-sonnet-4-5
```

### Step 5: Test It

```ruby
# Create a test pipeline with GPT-4
pipeline = PipelineExecution.create!(
  entity: entity,
  ticket_id: 'TEST-GPT4',
  ticket_title: 'Test GPT-4 code generation',
  ticket_description: 'Simple test to compare GPT-4 vs Claude',
  # ...
)

# Agent will use GPT-4 if CODER_MODEL=gpt-4-turbo-preview
ProcessPipelineJob.perform_later(pipeline.id)
```

---

## 🎯 Example 4: Google Gemini Integration

```ruby
# app/services/ai_providers/gemini_provider.rb
module AiProviders
  class GeminiProvider
    GEMINI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta'

    def initialize(api_key: ENV['GOOGLE_API_KEY'])
      @api_key = api_key
    end

    def generate(prompt, options = {})
      model = options[:model] || 'gemini-pro'

      response = HTTParty.post(
        "#{GEMINI_ENDPOINT}/models/#{model}:generateContent",
        query: { key: @api_key },
        headers: { 'Content-Type' => 'application/json' },
        body: {
          contents: [{
            parts: [{ text: build_full_prompt(prompt, options[:system_prompt]) }]
          }],
          generationConfig: {
            temperature: options[:temperature] || 0.7,
            maxOutputTokens: options[:max_tokens] || 4000
          }
        }.to_json
      )

      data = JSON.parse(response.body)

      {
        content: data.dig('candidates', 0, 'content', 'parts', 0, 'text'),
        usage: {
          input_tokens: data.dig('usageMetadata', 'promptTokenCount'),
          output_tokens: data.dig('usageMetadata', 'candidatesTokenCount')
        },
        model: model
      }
    end

    def calculate_cost(model, usage)
      input_tokens = usage[:input_tokens] || 0
      output_tokens = usage[:output_tokens] || 0

      case model
      when 'gemini-pro'
        # Free tier: 60 requests/minute
        # Paid: $0.50/$1.50 per 1M tokens
        (input_tokens / 1_000_000.0 * 0.50) + (output_tokens / 1_000_000.0 * 1.50)
      when 'gemini-ultra'
        # $10/$30 per 1M tokens (estimated)
        (input_tokens / 1_000_000.0 * 10.0) + (output_tokens / 1_000_000.0 * 30.0)
      else
        0.0
      end
    end

    private

    def build_full_prompt(user_prompt, system_prompt)
      if system_prompt
        "#{system_prompt}\n\n#{user_prompt}"
      else
        user_prompt
      end
    end
  end
end
```

---

## 📊 Cost Comparison Table

| Model | Input (per 1M tokens) | Output (per 1M tokens) | Best For |
|-------|----------------------|------------------------|----------|
| **Claude Haiku 3.5** | $1.00 | $5.00 | Clarification (fast, cheap) |
| **Claude Sonnet 3.5** | $3.00 | $15.00 | Code review (balanced) |
| **Claude Sonnet 4.5** | $7.50 | $15.00 | Code generation (best quality) |
| **GPT-3.5 Turbo** | $0.50 | $1.50 | Ultra-cheap testing |
| **GPT-4 Turbo** | $10.00 | $30.00 | Alternative to Claude |
| **GPT-4** | $30.00 | $60.00 | Premium (expensive) |
| **Gemini Pro** | $0.50 | $1.50 | Budget option |
| **Gemini Ultra** | ~$10.00 | ~$30.00 | Premium Google |

---

## 🔧 Configuration: Mix and Match

You can use different models for different agents:

```ruby
# config/initializers/ai_pipeline.rb
PIPELINE_CONFIG = {
  agents: {
    clarifier: {
      model: 'claude-3-5-haiku-20241022',  # Fast, cheap
      provider: :bedrock
    },
    planner: {
      model: 'claude-sonnet-4-5-20250929',  # Best reasoning
      provider: :bedrock
    },
    coder: {
      model: 'gpt-4-turbo-preview',  # Alternative to Claude
      provider: :openai
    },
    reviewer: {
      model: 'claude-3-5-sonnet-20241022',  # Balanced
      provider: :bedrock
    }
  }
}

# In each agent
class CoderAgent < BaseAgent
  def model
    PIPELINE_CONFIG.dig(:agents, :coder, :model)
  end

  def provider
    PIPELINE_CONFIG.dig(:agents, :coder, :provider)
  end
end
```

---

## 📚 Summary

### Ticket System Integration

1. **Create client class** implementing `fetch_recent_tickets(since:)`
2. **Return standard format** with required fields
3. **Add to enum** in McpConnection model
4. **Add to factory** in `client` method
5. **Configure connection** with credentials and filters

### AI Model Integration

1. **Create provider class** implementing `generate(prompt, options)`
2. **Add cost calculation** method
3. **Update BedrockService** to route based on model name
4. **Configure environment** variables for API keys
5. **Set model in agent** via `model` method override

### Benefits

- ✅ **Pluggable architecture** - swap components easily
- ✅ **Cost optimization** - mix cheap and expensive models
- ✅ **Multi-tenant** - different entities can use different providers
- ✅ **Future-proof** - add new systems without changing core logic

---

**Which system do you want to integrate first? GitHub Issues or OpenAI?** 🚀
