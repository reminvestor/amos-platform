# Workflow Templates Seed Data

# Analytics Templates
WorkflowTemplate.find_or_create_by!(slug: 'customer_analysis_yearly') do |template|
  template.name = 'Annual Customer Analysis'
  template.category = 'customer_analysis'
  template.description = 'Comprehensive yearly analysis of customer data from integrated platforms'
  template.is_system = true
  template.template_spec = {
    'steps' => [
      {
        'id' => 'fetch_customer_data',
        'agent_role' => 'executor',
        'name' => 'Fetch Customer Data',
        'description' => 'Retrieve customer data from {{integration_name}}',
        'type' => 'tool_call',
        'config' => {
          'tool' => 'invoke_operation',
          'operation_id' => '{{integration_slug}}.list_customers.v2020-08-27'
        },
        'tool_allowlist' => ['list_connections', 'invoke_operation', 'fetch_next_page'],
        'canvas_allowlist' => ['dynamic_canvas'],
        'budgets' => { 'max_tool_calls' => 10, 'timeout_seconds' => 120 }
      },
      {
        'id' => 'analyze_by_month',
        'agent_role' => 'analyst',
        'name' => 'Monthly Breakdown',
        'description' => 'Analyze customer signups by month',
        'type' => 'tool_call',
        'config' => {
          'tool' => 'aggregate_artifact_data',
          'operation' => 'group_by_time',
          'time_field' => 'created',
          'time_bucket' => 'month'
        },
        'dependencies' => ['fetch_customer_data'],
        'tool_allowlist' => ['aggregate_artifact_data'],
        'canvas_allowlist' => ['dynamic_canvas'],
        'budgets' => { 'max_tool_calls' => 5, 'timeout_seconds' => 60 }
      },
      {
        'id' => 'analyze_by_plan',
        'agent_role' => 'analyst',
        'name' => 'Plan Distribution',
        'description' => 'Analyze customers by subscription plan',
        'type' => 'tool_call',
        'config' => {
          'tool' => 'aggregate_artifact_data',
          'operation' => 'group_by_field',
          'field' => 'plan'
        },
        'dependencies' => ['fetch_customer_data'],
        'tool_allowlist' => ['aggregate_artifact_data'],
        'canvas_allowlist' => ['dynamic_canvas'],
        'budgets' => { 'max_tool_calls' => 5, 'timeout_seconds' => 60 }
      },
      {
        'id' => 'top_customers',
        'agent_role' => 'analyst',
        'name' => 'Top Customers',
        'description' => 'Identify top customers by revenue',
        'type' => 'tool_call',
        'config' => {
          'tool' => 'aggregate_artifact_data',
          'operation' => 'top_k',
          'field' => 'total_spent',
          'k' => 20
        },
        'dependencies' => ['fetch_customer_data'],
        'tool_allowlist' => ['aggregate_artifact_data'],
        'canvas_allowlist' => ['dynamic_canvas'],
        'budgets' => { 'max_tool_calls' => 5, 'timeout_seconds' => 60 }
      },
      {
        'id' => 'generate_report',
        'agent_role' => 'analyst',
        'name' => 'Generate Report',
        'description' => 'Create comprehensive visualization',
        'type' => 'tool_call',
        'config' => {
          'tool' => 'create_dynamic_visualization'
        },
        'dependencies' => ['analyze_by_month', 'analyze_by_plan', 'top_customers'],
        'tool_allowlist' => ['create_dynamic_visualization'],
        'canvas_allowlist' => ['dynamic_canvas', 'analytics_dashboard'],
        'budgets' => { 'max_tool_calls' => 3, 'timeout_seconds' => 30 }
      },
      {
        'id' => 'verify_completeness',
        'agent_role' => 'verifier',
        'name' => 'Verify Analysis',
        'description' => 'Ensure analysis is complete and accurate',
        'type' => 'validation',
        'config' => {
          'rules' => [
            { 'type' => 'data_completeness', 'threshold' => 0.9 },
            { 'type' => 'time_coverage', 'expected' => '12_months' }
          ]
        },
        'dependencies' => ['generate_report'],
        'tool_allowlist' => [],
        'canvas_allowlist' => ['task_progress'],
        'budgets' => { 'max_tool_calls' => 2, 'timeout_seconds' => 30 }
      }
    ],
    'metadata' => {
      'keywords' => ['annual', 'yearly', 'customer', 'analysis', 'year'],
      'estimated_duration' => 300,
      'requires_integration' => true
    }
  }
end

WorkflowTemplate.find_or_create_by!(slug: 'campaign_performance_analysis') do |template|
  template.name = 'Campaign Performance Analysis'
  template.category = 'analytics'
  template.description = 'Analyze email campaign performance with detailed metrics'
  template.is_system = true
  template.template_spec = {
    'steps' => [
      {
        'id' => 'fetch_campaigns',
        'agent_role' => 'executor',
        'name' => 'Fetch Campaigns',
        'description' => 'Retrieve campaign data with metrics',
        'type' => 'tool_call',
        'config' => {
          'tool' => 'get_data',
          'object_type' => 'campaigns',
          'options' => { 'include_metrics' => true, 'date_range' => '{{time_period}}' }
        },
        'tool_allowlist' => ['get_data', 'get_schema'],
        'canvas_allowlist' => ['campaign_viewer'],
        'budgets' => { 'max_tool_calls' => 3, 'timeout_seconds' => 30 }
      },
      {
        'id' => 'analyze_metrics',
        'agent_role' => 'analyst',
        'name' => 'Analyze Metrics',
        'description' => 'Calculate performance statistics',
        'type' => 'tool_call',
        'config' => {
          'tool' => 'aggregate_artifact_data',
          'operation' => 'simple_stats'
        },
        'dependencies' => ['fetch_campaigns'],
        'tool_allowlist' => ['aggregate_artifact_data'],
        'canvas_allowlist' => ['dynamic_canvas'],
        'budgets' => { 'max_tool_calls' => 5, 'timeout_seconds' => 60 }
      },
      {
        'id' => 'create_visualization',
        'agent_role' => 'analyst',
        'name' => 'Create Visualization',
        'description' => 'Generate performance dashboard',
        'type' => 'tool_call',
        'config' => {
          'tool' => 'create_dynamic_visualization',
          'visualization_type' => 'campaign_dashboard'
        },
        'dependencies' => ['analyze_metrics'],
        'tool_allowlist' => ['create_dynamic_visualization'],
        'canvas_allowlist' => ['analytics_dashboard'],
        'budgets' => { 'max_tool_calls' => 3, 'timeout_seconds' => 30 }
      }
    ],
    'metadata' => {
      'keywords' => ['campaign', 'performance', 'email', 'metrics', 'analyze'],
      'estimated_duration' => 120
    }
  }
end

# Campaign Creation Templates
WorkflowTemplate.find_or_create_by!(slug: 'full_campaign_creation') do |template|
  template.name = 'Full Campaign Creation'
  template.category = 'campaign_creation'
  template.description = 'Create a complete email campaign with template and contacts'
  template.is_system = true
  template.template_spec = {
    'steps' => [
      {
        'id' => 'define_campaign',
        'agent_role' => 'executor',
        'name' => 'Define Campaign',
        'description' => 'Gather campaign details',
        'type' => 'user_input',
        'config' => {
          'fields' => [
            { 'name' => 'campaign_name', 'type' => 'text', 'required' => true },
            { 'name' => 'subject_line', 'type' => 'text', 'required' => true },
            { 'name' => 'target_audience', 'type' => 'text' },
            { 'name' => 'send_date', 'type' => 'date' }
          ]
        },
        'tool_allowlist' => [],
        'canvas_allowlist' => ['campaign_viewer']
      },
      {
        'id' => 'create_campaign',
        'agent_role' => 'executor',
        'name' => 'Create Campaign',
        'description' => 'Create the campaign record',
        'type' => 'tool_call',
        'config' => {
          'tool' => 'create_object',
          'object_type' => 'campaigns'
        },
        'dependencies' => ['define_campaign'],
        'tool_allowlist' => ['create_object', 'get_schema'],
        'canvas_allowlist' => ['campaign_viewer'],
        'budgets' => { 'max_tool_calls' => 3, 'timeout_seconds' => 30 }
      },
      {
        'id' => 'create_template',
        'agent_role' => 'executor',
        'name' => 'Create Email Template',
        'description' => 'Generate email template content',
        'type' => 'tool_call',
        'config' => {
          'tool' => 'create_object',
          'object_type' => 'email_templates'
        },
        'dependencies' => ['create_campaign'],
        'tool_allowlist' => ['create_object', 'get_schema'],
        'canvas_allowlist' => ['email_template_editor'],
        'budgets' => { 'max_tool_calls' => 3, 'timeout_seconds' => 30 }
      },
      {
        'id' => 'link_template',
        'agent_role' => 'executor',
        'name' => 'Link Template',
        'description' => 'Link email template to campaign',
        'type' => 'tool_call',
        'config' => {
          'tool' => 'link_template_to_campaign'
        },
        'dependencies' => ['create_template'],
        'tool_allowlist' => ['link_template_to_campaign'],
        'canvas_allowlist' => ['campaign_viewer'],
        'budgets' => { 'max_tool_calls' => 2, 'timeout_seconds' => 30 }
      },
      {
        'id' => 'verify_campaign',
        'agent_role' => 'verifier',
        'name' => 'Verify Campaign',
        'description' => 'Verify campaign is ready to send',
        'type' => 'validation',
        'config' => {
          'rules' => [
            { 'type' => 'has_template', 'required' => true },
            { 'type' => 'has_recipients', 'min_count' => 1 },
            { 'type' => 'valid_content', 'check_personalization' => true }
          ]
        },
        'dependencies' => ['link_template'],
        'tool_allowlist' => ['get_data'],
        'canvas_allowlist' => ['task_progress'],
        'budgets' => { 'max_tool_calls' => 3, 'timeout_seconds' => 30 }
      }
    ],
    'metadata' => {
      'keywords' => ['create', 'campaign', 'email', 'template', 'new'],
      'estimated_duration' => 180
    }
  }
end

# Data Import Templates
WorkflowTemplate.find_or_create_by!(slug: 'integration_data_sync') do |template|
  template.name = 'Integration Data Sync'
  template.category = 'data_import'
  template.description = 'Sync data from external integrations'
  template.is_system = true
  template.template_spec = {
    'steps' => [
      {
        'id' => 'list_integrations',
        'agent_role' => 'executor',
        'name' => 'List Available Integrations',
        'description' => 'Show available data sources',
        'type' => 'tool_call',
        'config' => {
          'tool' => 'list_connections'
        },
        'tool_allowlist' => ['list_connections'],
        'canvas_allowlist' => ['integrations_manager'],
        'budgets' => { 'max_tool_calls' => 2, 'timeout_seconds' => 30 }
      },
      {
        'id' => 'select_source',
        'agent_role' => 'executor',
        'name' => 'Select Data Source',
        'description' => 'Choose integration to sync from',
        'type' => 'user_input',
        'config' => {
          'fields' => [
            { 'name' => 'connection_id', 'type' => 'select', 'required' => true },
            { 'name' => 'operation_id', 'type' => 'select', 'required' => true },
            { 'name' => 'sync_all', 'type' => 'checkbox', 'default' => false }
          ]
        },
        'dependencies' => ['list_integrations'],
        'tool_allowlist' => ['describe_connection'],
        'canvas_allowlist' => ['integrations_manager']
      },
      {
        'id' => 'import_data',
        'agent_role' => 'executor',
        'name' => 'Import Data',
        'description' => 'Execute data import',
        'type' => 'tool_call',
        'config' => {
          'tool' => 'invoke_operation'
        },
        'dependencies' => ['select_source'],
        'tool_allowlist' => ['invoke_operation', 'fetch_next_page'],
        'canvas_allowlist' => ['dynamic_canvas'],
        'budgets' => { 'max_tool_calls' => 20, 'timeout_seconds' => 300 }
      },
      {
        'id' => 'process_data',
        'agent_role' => 'analyst',
        'name' => 'Process Imported Data',
        'description' => 'Analyze and organize imported data',
        'type' => 'tool_call',
        'config' => {
          'tool' => 'aggregate_artifact_data',
          'operation' => 'simple_stats'
        },
        'dependencies' => ['import_data'],
        'tool_allowlist' => ['aggregate_artifact_data'],
        'canvas_allowlist' => ['dynamic_canvas'],
        'budgets' => { 'max_tool_calls' => 5, 'timeout_seconds' => 60 }
      }
    ],
    'metadata' => {
      'keywords' => ['import', 'sync', 'integration', 'fetch', 'data'],
      'estimated_duration' => 300,
      'requires_integration' => true
    }
  }
end

# Add the App Connection Creation template if the workflow class exists
begin
  if defined?(Workflows::AppConnectionWorkflow)
    WorkflowTemplate.find_or_create_by!(slug: 'create-app-connection') do |template|
      template.name = "Create App Connection"
      template.description = "Interactively create a new integration with AI assistance"
      template.category = "integration"
      template.template_spec = Workflows::AppConnectionWorkflow.new.to_h
      template.is_active = true
    end
  end
rescue => e
  puts "Warning: Could not create app connection workflow template: #{e.message}"
end

puts "Created #{WorkflowTemplate.count} workflow templates"
