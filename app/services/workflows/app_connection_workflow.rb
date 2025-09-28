module Workflows
  class AppConnectionWorkflow
    attr_reader :name, :description, :steps

    def initialize
      @name = "Create App Connection"
      @description = "Interactively create a new integration connection with AI assistance"
      @steps = build_steps
    end

    def to_h
      {
        name: @name,
        description: @description,
        steps: @steps.map(&:to_h)
      }
    end

    private

    def build_steps
      [
        # Step 1: Gather initial requirements
        Step.new(
          id: 'gather_requirements',
          name: 'Gather App Requirements',
          type: 'user_input',
          config: {
            form_fields: [
              {
                name: 'app_name',
                label: 'What application do you want to integrate?',
                type: 'text',
                required: true,
                placeholder: 'e.g., Slack, Salesforce, Shopify'
              },
              {
                name: 'use_case',
                label: 'What do you want to do with this integration?',
                type: 'textarea',
                required: true,
                placeholder: 'Describe your use case and what data/actions you need'
              },
              {
                name: 'existing_docs',
                label: 'Do you have any API documentation or links?',
                type: 'textarea',
                required: false,
                placeholder: 'Paste any URLs or documentation you already have'
              }
            ]
          }
        ),

        # Step 2: Web search for API documentation
        Step.new(
          id: 'search_api_docs',
          name: 'Search for API Documentation',
          type: 'tool_call',
          dependencies: ['gather_requirements'],
          tool_allowlist: ['web_search'],
          config: {
            tool: 'web_search',
            prompt_template: "Search for official API documentation for <%= inputs['app_name'] %>. Focus on: authentication methods, REST API endpoints, rate limits, and getting started guides."
          }
        ),

        # Step 3: Present findings and gather feedback
        Step.new(
          id: 'review_findings',
          name: 'Review API Documentation Findings',
          type: 'user_input',
          dependencies: ['search_api_docs'],
          config: {
            display_context: true,
            form_fields: [
              {
                name: 'feedback',
                label: 'Does this look correct? Any additional information to add?',
                type: 'textarea',
                required: false
              },
              {
                name: 'additional_docs',
                label: 'Upload any API documentation files (PDF, JSON, etc.)',
                type: 'file_upload',
                required: false,
                accept: '.pdf,.json,.yaml,.yml,.txt,.md',
                multiple: true
              },
              {
                name: 'api_key_location',
                label: 'Where do you get API keys for this service?',
                type: 'text',
                required: false,
                placeholder: 'e.g., https://app.example.com/settings/api'
              }
            ]
          }
        ),

        # Step 4: Create RAG store from documentation
        Step.new(
          id: 'create_rag_store',
          name: 'Build Knowledge Base',
          type: 'tool_call',
          dependencies: ['review_findings'],
          tool_allowlist: ['create_rag_store'],
          config: {
            tool: 'create_rag_store',
            prompt_template: "Create a RAG store for <%= inputs['app_name'] %> API using the gathered documentation and user uploads."
          }
        ),

        # Step 5: Generate initial integration code
        Step.new(
          id: 'generate_integration',
          name: 'Generate Integration Configuration',
          type: 'tool_call',
          dependencies: ['create_rag_store'],
          tool_allowlist: ['generate_integration_config'],
          config: {
            tool: 'generate_integration_config',
            prompt_template: "Generate the initial integration configuration for <%= inputs['app_name'] %> including authentication setup and one test endpoint based on the use case: <%= inputs['use_case'] %>"
          }
        ),

        # Step 6: Test the initial endpoint
        Step.new(
          id: 'test_endpoint',
          name: 'Test Initial Endpoint',
          type: 'user_input',
          dependencies: ['generate_integration'],
          config: {
            display_context: true,
            form_fields: [
              {
                name: 'api_credentials',
                label: 'Enter your API credentials',
                type: 'json',
                required: true,
                schema: 'dynamic' # Will be populated based on auth requirements
              },
              {
                name: 'test_params',
                label: 'Test parameters (if needed)',
                type: 'json',
                required: false
              }
            ],
            actions: [
              {
                name: 'test_connection',
                label: 'Test Connection',
                type: 'tool_call',
                tool: 'test_integration_endpoint'
              }
            ]
          }
        ),

        # Step 7: Review test results and iterate
        Step.new(
          id: 'review_test_results',
          name: 'Review Test Results',
          type: 'user_input',
          dependencies: ['test_endpoint'],
          config: {
            display_context: true,
            form_fields: [
              {
                name: 'test_feedback',
                label: 'How did the test go? Any issues?',
                type: 'textarea',
                required: true
              },
              {
                name: 'proceed',
                label: 'Ready to build out remaining endpoints?',
                type: 'select',
                required: true,
                options: [
                  { value: 'yes', label: 'Yes, continue building' },
                  { value: 'iterate', label: 'No, let\'s fix issues first' },
                  { value: 'cancel', label: 'Cancel integration creation' }
                ]
              }
            ]
          }
        ),

        # Step 8: Build remaining endpoints
        Step.new(
          id: 'build_full_integration',
          name: 'Build Complete Integration',
          type: 'tool_call',
          dependencies: ['review_test_results'],
          condition: "inputs['proceed'] == 'yes'",
          tool_allowlist: ['build_integration_endpoints'],
          config: {
            tool: 'build_integration_endpoints',
            prompt_template: "Build out all remaining endpoints for <%= inputs['app_name'] %> based on the use case and successful test pattern."
          }
        ),

        # Step 9: Final review and activation
        Step.new(
          id: 'final_review',
          name: 'Final Review and Activation',
          type: 'user_input',
          dependencies: ['build_full_integration'],
          config: {
            display_context: true,
            form_fields: [
              {
                name: 'integration_name',
                label: 'Name for this integration',
                type: 'text',
                required: true,
                default_template: "<%= inputs['app_name'] %> Integration"
              },
              {
                name: 'description',
                label: 'Description',
                type: 'textarea',
                required: false
              },
              {
                name: 'activate',
                label: 'Activate this integration?',
                type: 'checkbox',
                default: true
              }
            ]
          }
        )
      ]
    end
  end
end
