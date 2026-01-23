# frozen_string_literal: true

module Workflows
  # NodeRegistry defines all available workflow node types with their schemas.
  # This serves as the single source of truth for what nodes exist and how they
  # should be configured, validated, and executed.
  #
  # Node Categories:
  # - trigger: Entry points that start a workflow
  # - action: Nodes that do something (call API, send email, create record)
  # - logic: Control flow (conditions, switches, loops)
  # - transform: Data manipulation (map, filter, aggregate)
  # - integration: External service calls
  # - agent: AI agent invocations
  #
  class NodeRegistry
    include Singleton

    # All registered node types
    NODE_TYPES = {
      # ═══════════════════════════════════════════════════════════════
      # TRIGGER NODES - Entry points that start workflows
      # ═══════════════════════════════════════════════════════════════

      'trigger-form' => {
        category: 'trigger',
        label: 'Form Submission',
        description: 'Triggers when a form is submitted on a landing page or website',
        icon: 'file-text',
        color: '#10b981',  # Green
        inputs: [],
        outputs: [
          { name: 'submission', type: 'object', description: 'The form submission data' },
          { name: 'submitter', type: 'object', description: 'Info about who submitted' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            landing_page_id: { type: 'integer', title: 'Landing Page' },
            website_page_id: { type: 'integer', title: 'Website Page' },
            form_selector: { type: 'string', title: 'Form Selector', description: 'CSS selector if multiple forms' }
          }
        },
        executor: 'Workflows::Executors::FormTriggerExecutor'
      },

      'trigger-webhook' => {
        category: 'trigger',
        label: 'Webhook',
        description: 'Triggers when an external service calls a webhook URL',
        icon: 'webhook',
        color: '#10b981',
        inputs: [],
        outputs: [
          { name: 'payload', type: 'object', description: 'The webhook payload' },
          { name: 'headers', type: 'object', description: 'Request headers' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            webhook_path: { type: 'string', title: 'Webhook Path', required: true },
            auth_type: { type: 'string', enum: ['none', 'api_key', 'hmac'], title: 'Authentication' },
            secret: { type: 'string', title: 'Secret Key', format: 'password' }
          }
        },
        executor: 'Workflows::Executors::WebhookTriggerExecutor'
      },

      'trigger-schedule' => {
        category: 'trigger',
        label: 'Scheduled',
        description: 'Triggers on a schedule (cron or interval)',
        icon: 'clock',
        color: '#10b981',
        inputs: [],
        outputs: [
          { name: 'trigger_time', type: 'datetime', description: 'When this trigger fired' },
          { name: 'run_count', type: 'integer', description: 'How many times this has run' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            schedule_type: { type: 'string', enum: ['cron', 'interval'], title: 'Schedule Type', required: true },
            cron_expression: { type: 'string', title: 'Cron Expression' },
            interval_minutes: { type: 'integer', title: 'Interval (minutes)' },
            timezone: { type: 'string', title: 'Timezone', default: 'UTC' }
          }
        },
        executor: 'Workflows::Executors::ScheduleTriggerExecutor'
      },

      'trigger-record' => {
        category: 'trigger',
        label: 'Record Event',
        description: 'Triggers when a record is created, updated, or deleted in a module',
        icon: 'database',
        color: '#10b981',
        inputs: [],
        outputs: [
          { name: 'record', type: 'object', description: 'The affected record' },
          { name: 'changes', type: 'object', description: 'What fields changed' },
          { name: 'event_type', type: 'string', description: 'created, updated, or deleted' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            app_module_id: { type: 'integer', title: 'Module', required: true },
            event_types: { type: 'array', items: { type: 'string', enum: ['created', 'updated', 'deleted'] }, title: 'Events' },
            field_filter: { type: 'string', title: 'Only when field changes' },
            condition: { type: 'string', title: 'Additional condition (e.g., status = "active")' }
          }
        },
        executor: 'Workflows::Executors::RecordTriggerExecutor'
      },

      'trigger-manual' => {
        category: 'trigger',
        label: 'Manual Trigger',
        description: 'Triggered manually by a user or agent',
        icon: 'play',
        color: '#10b981',
        inputs: [],
        outputs: [
          { name: 'context', type: 'object', description: 'Context passed when triggered' },
          { name: 'triggered_by', type: 'object', description: 'User or agent that triggered' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            input_schema: { type: 'object', title: 'Expected Input Schema' },
            require_confirmation: { type: 'boolean', title: 'Require User Confirmation', default: false }
          }
        },
        executor: 'Workflows::Executors::ManualTriggerExecutor'
      },

      # ═══════════════════════════════════════════════════════════════
      # ACTION NODES - Do something
      # ═══════════════════════════════════════════════════════════════

      'action-email' => {
        category: 'action',
        label: 'Send Email',
        description: 'Send an email using configured email service',
        icon: 'mail',
        color: '#3b82f6',  # Blue
        inputs: [
          { name: 'to', type: 'string', description: 'Recipient email', required: true },
          { name: 'subject', type: 'string', description: 'Email subject' },
          { name: 'body', type: 'string', description: 'Email body' }
        ],
        outputs: [
          { name: 'sent', type: 'boolean', description: 'Whether email was sent' },
          { name: 'message_id', type: 'string', description: 'Email service message ID' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            from: { type: 'string', title: 'From Address' },
            template_id: { type: 'integer', title: 'Email Template' },
            subject_template: { type: 'string', title: 'Subject (supports {{variables}})' },
            body_template: { type: 'string', title: 'Body (supports {{variables}})', format: 'textarea' },
            html: { type: 'boolean', title: 'Send as HTML', default: true }
          }
        },
        executor: 'Workflows::Executors::EmailActionExecutor'
      },

      'action-create-record' => {
        category: 'action',
        label: 'Create Record',
        description: 'Create a new record in a module',
        icon: 'plus-circle',
        color: '#3b82f6',
        inputs: [
          { name: 'data', type: 'object', description: 'Record data to create' }
        ],
        outputs: [
          { name: 'record', type: 'object', description: 'The created record' },
          { name: 'id', type: 'integer', description: 'The new record ID' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            app_module_id: { type: 'integer', title: 'Target Module', required: true },
            field_mapping: { type: 'object', title: 'Field Mapping', description: 'Map input fields to module fields' },
            default_values: { type: 'object', title: 'Default Values' }
          }
        },
        executor: 'Workflows::Executors::CreateRecordExecutor'
      },

      'action-update-record' => {
        category: 'action',
        label: 'Update Record',
        description: 'Update an existing record in a module',
        icon: 'edit',
        color: '#3b82f6',
        inputs: [
          { name: 'record_id', type: 'integer', description: 'ID of record to update', required: true },
          { name: 'data', type: 'object', description: 'Fields to update' }
        ],
        outputs: [
          { name: 'record', type: 'object', description: 'The updated record' },
          { name: 'changes', type: 'object', description: 'What was changed' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            app_module_id: { type: 'integer', title: 'Target Module', required: true },
            field_mapping: { type: 'object', title: 'Field Mapping' },
            find_by: { type: 'string', title: 'Find record by field (if not using record_id)' }
          }
        },
        executor: 'Workflows::Executors::UpdateRecordExecutor'
      },

      'action-http-request' => {
        category: 'action',
        label: 'HTTP Request',
        description: 'Make an HTTP request to an external API',
        icon: 'globe',
        color: '#3b82f6',
        inputs: [
          { name: 'url', type: 'string', description: 'Request URL' },
          { name: 'body', type: 'object', description: 'Request body' },
          { name: 'headers', type: 'object', description: 'Additional headers' }
        ],
        outputs: [
          { name: 'response', type: 'object', description: 'Response body' },
          { name: 'status', type: 'integer', description: 'HTTP status code' },
          { name: 'headers', type: 'object', description: 'Response headers' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            method: { type: 'string', enum: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'], title: 'Method', required: true },
            url_template: { type: 'string', title: 'URL (supports {{variables}})' },
            headers: { type: 'object', title: 'Default Headers' },
            body_template: { type: 'string', title: 'Body Template', format: 'json' },
            timeout_seconds: { type: 'integer', title: 'Timeout (seconds)', default: 30 }
          }
        },
        executor: 'Workflows::Executors::HttpRequestExecutor'
      },

      'action-delay' => {
        category: 'action',
        label: 'Delay',
        description: 'Wait for a specified amount of time',
        icon: 'clock',
        color: '#3b82f6',
        inputs: [],
        outputs: [
          { name: 'resumed_at', type: 'datetime', description: 'When the delay ended' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            delay_type: { type: 'string', enum: ['fixed', 'until_time', 'until_condition'], title: 'Delay Type' },
            delay_minutes: { type: 'integer', title: 'Delay (minutes)' },
            delay_until: { type: 'string', title: 'Delay until (datetime or expression)' }
          }
        },
        executor: 'Workflows::Executors::DelayExecutor'
      },

      # ═══════════════════════════════════════════════════════════════
      # LOGIC NODES - Control flow
      # ═══════════════════════════════════════════════════════════════

      'logic-condition' => {
        category: 'logic',
        label: 'Condition (If/Else)',
        description: 'Branch workflow based on a condition',
        icon: 'git-branch',
        color: '#f59e0b',  # Amber
        inputs: [
          { name: 'value', type: 'any', description: 'Value to evaluate' }
        ],
        outputs: [
          { name: 'true', type: 'any', description: 'Output if condition is true', port: 'right' },
          { name: 'false', type: 'any', description: 'Output if condition is false', port: 'bottom' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            field: { type: 'string', title: 'Field to check', required: true },
            operator: { 
              type: 'string', 
              enum: ['equals', 'not_equals', 'contains', 'not_contains', 'greater_than', 'less_than', 'is_empty', 'is_not_empty', 'matches_regex'],
              title: 'Operator',
              required: true
            },
            compare_to: { type: 'string', title: 'Compare to value' }
          }
        },
        executor: 'Workflows::Executors::ConditionExecutor'
      },

      'logic-switch' => {
        category: 'logic',
        label: 'Switch (Multiple Paths)',
        description: 'Route to different paths based on value',
        icon: 'git-merge',
        color: '#f59e0b',
        inputs: [
          { name: 'value', type: 'any', description: 'Value to switch on' }
        ],
        outputs: [
          { name: 'default', type: 'any', description: 'Default output if no case matches' }
          # Additional outputs are dynamically added based on cases
        ],
        config_schema: {
          type: 'object',
          properties: {
            field: { type: 'string', title: 'Field to switch on', required: true },
            cases: { 
              type: 'array', 
              title: 'Cases',
              items: {
                type: 'object',
                properties: {
                  value: { type: 'string', title: 'When value equals' },
                  output_name: { type: 'string', title: 'Output port name' }
                }
              }
            }
          }
        },
        executor: 'Workflows::Executors::SwitchExecutor'
      },

      'logic-loop' => {
        category: 'logic',
        label: 'Loop (For Each)',
        description: 'Iterate over an array of items',
        icon: 'repeat',
        color: '#f59e0b',
        inputs: [
          { name: 'items', type: 'array', description: 'Array to iterate over', required: true }
        ],
        outputs: [
          { name: 'item', type: 'any', description: 'Current item in iteration' },
          { name: 'index', type: 'integer', description: 'Current index' },
          { name: 'completed', type: 'array', description: 'All results after loop completes' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            items_field: { type: 'string', title: 'Field containing array', required: true },
            max_iterations: { type: 'integer', title: 'Max iterations (safety limit)', default: 100 },
            parallel: { type: 'boolean', title: 'Run iterations in parallel', default: false }
          }
        },
        executor: 'Workflows::Executors::LoopExecutor'
      },

      'logic-merge' => {
        category: 'logic',
        label: 'Merge',
        description: 'Combine multiple branches back together',
        icon: 'git-pull-request',
        color: '#f59e0b',
        inputs: [
          { name: 'input_1', type: 'any', description: 'First input' },
          { name: 'input_2', type: 'any', description: 'Second input' }
          # Can have more inputs
        ],
        outputs: [
          { name: 'merged', type: 'object', description: 'Merged data from all inputs' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            merge_mode: { type: 'string', enum: ['wait_all', 'first_wins', 'combine'], title: 'Merge Mode' },
            output_structure: { type: 'object', title: 'Output structure mapping' }
          }
        },
        executor: 'Workflows::Executors::MergeExecutor'
      },

      # ═══════════════════════════════════════════════════════════════
      # TRANSFORM NODES - Data manipulation
      # ═══════════════════════════════════════════════════════════════

      'transform-map' => {
        category: 'transform',
        label: 'Map Fields',
        description: 'Transform and rename fields in data',
        icon: 'shuffle',
        color: '#8b5cf6',  # Purple
        inputs: [
          { name: 'data', type: 'object', description: 'Input data to transform' }
        ],
        outputs: [
          { name: 'result', type: 'object', description: 'Transformed data' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            mapping: { 
              type: 'array', 
              title: 'Field Mappings',
              items: {
                type: 'object',
                properties: {
                  source: { type: 'string', title: 'Source field' },
                  target: { type: 'string', title: 'Target field' },
                  transform: { type: 'string', title: 'Transform expression' }
                }
              }
            }
          }
        },
        executor: 'Workflows::Executors::MapTransformExecutor'
      },

      'transform-filter' => {
        category: 'transform',
        label: 'Filter Array',
        description: 'Filter items in an array based on conditions',
        icon: 'filter',
        color: '#8b5cf6',
        inputs: [
          { name: 'items', type: 'array', description: 'Array to filter' }
        ],
        outputs: [
          { name: 'matched', type: 'array', description: 'Items that matched the filter' },
          { name: 'rejected', type: 'array', description: 'Items that did not match' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            field: { type: 'string', title: 'Field to check' },
            operator: { type: 'string', enum: ['equals', 'not_equals', 'contains', 'greater_than', 'less_than'], title: 'Operator' },
            value: { type: 'string', title: 'Compare to' }
          }
        },
        executor: 'Workflows::Executors::FilterTransformExecutor'
      },

      'transform-aggregate' => {
        category: 'transform',
        label: 'Aggregate',
        description: 'Aggregate values (sum, count, average, etc.)',
        icon: 'calculator',
        color: '#8b5cf6',
        inputs: [
          { name: 'items', type: 'array', description: 'Array to aggregate' }
        ],
        outputs: [
          { name: 'result', type: 'number', description: 'Aggregated result' },
          { name: 'details', type: 'object', description: 'Breakdown details' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            operation: { type: 'string', enum: ['sum', 'count', 'average', 'min', 'max', 'first', 'last'], title: 'Operation' },
            field: { type: 'string', title: 'Field to aggregate' },
            group_by: { type: 'string', title: 'Group by field (optional)' }
          }
        },
        executor: 'Workflows::Executors::AggregateTransformExecutor'
      },

      'transform-code' => {
        category: 'transform',
        label: 'Custom Code',
        description: 'Execute custom Ruby transformation code (AI-generated)',
        icon: 'code',
        color: '#8b5cf6',
        inputs: [
          { name: 'data', type: 'any', description: 'Input data' }
        ],
        outputs: [
          { name: 'result', type: 'any', description: 'Transformed output' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            code: { type: 'string', title: 'Ruby Code', format: 'code', required: true },
            description: { type: 'string', title: 'What this code does' },
            ai_generated: { type: 'boolean', title: 'AI Generated', default: true },
            tested: { type: 'boolean', title: 'Has been tested', default: false }
          }
        },
        executor: 'Workflows::Executors::CodeTransformExecutor'
      },

      # ═══════════════════════════════════════════════════════════════
      # INTEGRATION NODES - External services
      # ═══════════════════════════════════════════════════════════════

      'integration-call' => {
        category: 'integration',
        label: 'Integration Action',
        description: 'Call an action on a connected integration',
        icon: 'link',
        color: '#ec4899',  # Pink
        inputs: [
          { name: 'params', type: 'object', description: 'Action parameters' }
        ],
        outputs: [
          { name: 'result', type: 'object', description: 'Integration response' },
          { name: 'success', type: 'boolean', description: 'Whether action succeeded' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            integration_id: { type: 'integer', title: 'Integration', required: true },
            action: { type: 'string', title: 'Action to perform', required: true },
            param_mapping: { type: 'object', title: 'Parameter mapping' }
          }
        },
        executor: 'Workflows::Executors::IntegrationCallExecutor'
      },

      # ═══════════════════════════════════════════════════════════════
      # AGENT NODES - AI agent invocations
      # ═══════════════════════════════════════════════════════════════

      'agent-invoke' => {
        category: 'agent',
        label: 'Invoke Agent',
        description: 'Send a task to an AI agent and wait for response',
        icon: 'bot',
        color: '#06b6d4',  # Cyan
        inputs: [
          { name: 'context', type: 'object', description: 'Context for the agent' },
          { name: 'prompt', type: 'string', description: 'Task prompt' }
        ],
        outputs: [
          { name: 'response', type: 'string', description: 'Agent response' },
          { name: 'artifacts', type: 'array', description: 'Any artifacts created' },
          { name: 'success', type: 'boolean', description: 'Whether agent succeeded' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            agent_id: { type: 'integer', title: 'Agent', required: true },
            prompt_template: { type: 'string', title: 'Prompt template (supports {{variables}})', format: 'textarea' },
            wait_for_completion: { type: 'boolean', title: 'Wait for agent to finish', default: true },
            timeout_minutes: { type: 'integer', title: 'Timeout (minutes)', default: 5 }
          }
        },
        executor: 'Workflows::Executors::AgentInvokeExecutor'
      },

      'agent-decide' => {
        category: 'agent',
        label: 'AI Decision',
        description: 'Let AI make a decision based on context',
        icon: 'brain',
        color: '#06b6d4',
        inputs: [
          { name: 'context', type: 'object', description: 'Decision context' }
        ],
        outputs: [
          { name: 'decision', type: 'string', description: 'The AI decision' },
          { name: 'reasoning', type: 'string', description: 'Why this decision was made' },
          { name: 'confidence', type: 'number', description: 'Confidence score (0-1)' }
        ],
        config_schema: {
          type: 'object',
          properties: {
            decision_prompt: { type: 'string', title: 'Decision prompt', format: 'textarea', required: true },
            options: { type: 'array', items: { type: 'string' }, title: 'Possible decisions (optional)' },
            context_template: { type: 'string', title: 'Context template', format: 'textarea' }
          }
        },
        executor: 'Workflows::Executors::AgentDecideExecutor'
      },

      # ═══════════════════════════════════════════════════════════════
      # OUTPUT NODES - End points
      # ═══════════════════════════════════════════════════════════════

      'output-success' => {
        category: 'output',
        label: 'Success',
        description: 'Mark workflow as successfully completed',
        icon: 'check-circle',
        color: '#22c55e',  # Green
        inputs: [
          { name: 'data', type: 'any', description: 'Final output data' }
        ],
        outputs: [],
        config_schema: {
          type: 'object',
          properties: {
            message: { type: 'string', title: 'Success message' },
            notify_user: { type: 'boolean', title: 'Notify user on completion', default: false }
          }
        },
        executor: 'Workflows::Executors::SuccessOutputExecutor'
      },

      'output-error' => {
        category: 'output',
        label: 'Error',
        description: 'Mark workflow as failed with error',
        icon: 'x-circle',
        color: '#ef4444',  # Red
        inputs: [
          { name: 'error', type: 'any', description: 'Error information' }
        ],
        outputs: [],
        config_schema: {
          type: 'object',
          properties: {
            error_message: { type: 'string', title: 'Error message' },
            retry_allowed: { type: 'boolean', title: 'Allow retry', default: true },
            notify_user: { type: 'boolean', title: 'Notify user on error', default: true }
          }
        },
        executor: 'Workflows::Executors::ErrorOutputExecutor'
      }
    }.freeze

    # Get all node types
    def all
      NODE_TYPES
    end

    # Get node type by key
    def get(type_key)
      NODE_TYPES[type_key]
    end

    # Get nodes by category
    def by_category(category)
      NODE_TYPES.select { |_, v| v[:category] == category.to_s }
    end

    # Get all categories
    def categories
      NODE_TYPES.values.map { |v| v[:category] }.uniq
    end

    # Validate a node configuration
    def validate_node(type_key, config)
      node_type = get(type_key)
      return { valid: false, errors: ["Unknown node type: #{type_key}"] } unless node_type

      errors = []
      schema = node_type[:config_schema]

      if schema && schema[:properties]
        schema[:properties].each do |field, field_schema|
          if field_schema[:required] && (config[field.to_s].blank? && config[field.to_sym].blank?)
            errors << "#{field_schema[:title] || field} is required"
          end
        end
      end

      { valid: errors.empty?, errors: errors }
    end

    # Get the executor class for a node type
    def executor_for(type_key)
      node_type = get(type_key)
      return nil unless node_type

      executor_class_name = node_type[:executor]
      return nil unless executor_class_name

      executor_class_name.constantize
    rescue NameError
      Rails.logger.warn "[NodeRegistry] Executor not found: #{executor_class_name}"
      nil
    end

    # Get node types formatted for the UI
    def for_ui
      NODE_TYPES.map do |key, node|
        {
          type: key,
          label: node[:label],
          description: node[:description],
          category: node[:category],
          icon: node[:icon],
          color: node[:color],
          inputs: node[:inputs],
          outputs: node[:outputs],
          config_schema: node[:config_schema]
        }
      end
    end

    # Get node types grouped by category for UI palette
    def palette
      by_cat = NODE_TYPES.group_by { |_, v| v[:category] }
      
      by_cat.transform_values do |nodes|
        nodes.map do |key, node|
          {
            type: key,
            label: node[:label],
            icon: node[:icon],
            color: node[:color],
            description: node[:description]
          }
        end
      end
    end
  end
end
