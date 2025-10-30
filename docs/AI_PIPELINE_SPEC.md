# ============================================================
# AI+Human Dev Pipeline Specification
# Version: 2.0 (Implementation Ready)
# Compatible with: AMOS / Claude Code / MCP Ecosystem
# Last Updated: 2025-01-28
# Status: Ready for Development
# ============================================================
#
# IMPLEMENTATION DECISIONS:
# - Orchestration: SolidQueue (Rails-native, existing infrastructure)
# - Agent Workspaces: Isolated /tmp directories with 0700 permissions
# - Git Providers: GitHub + Azure Repos (dual support)
# - Ticket Systems: JIRA Cloud + Azure DevOps (dual support)
# - Database: PostgreSQL with JSONB for flexibility
# - Notification: Slack/Teams/Email adapter pattern
# - AI Provider: AWS Bedrock Claude (via existing BedrockService)
# ============================================================

pipeline:
  name: ai_dev_pipeline
  description: >
    End-to-end development pipeline integrating AI agents, humans, and CI/CD
    tools. Automates ticket triage, coding, testing, and promotion using
    JIRA or Azure DevOps MCP clients as input sources.

  objectives:
    - Minimize cycle time from ticket to production.
    - Preserve human oversight where risk or ambiguity exists.
    - Ensure auditability, security, and quality at each stage.
    - Enable incremental rollout and rollback through feature flags.

# ------------------------------------------------------------
#  ORCHESTRATION
# ------------------------------------------------------------
orchestration:
  engine: solid_queue  # Rails-native background job processor
  queues:
    pipeline: priority 10  # Main orchestration
    agents: priority 8     # AI agent execution
    notifications: priority 6
    maintenance: priority 2
  error_handling:
    max_retries: 3
    backoff_strategy: exponential
    failed_jobs_retention: 7_days
  agent_concurrency:
    max_parallel_tickets: 5
    max_parallel_agents: 10
    max_tokens_per_hour: 1000000
  scheduling:
    batch_processing: true
    priority_lanes:
      critical: immediate
      normal: queue
      low: batch
  recurring_jobs:
    - cleanup_workspaces: every hour
    - sync_ticket_systems: every 5 minutes
    - health_check_connections: every 15 minutes

# ------------------------------------------------------------
#  AGENT DEFINITIONS
# ------------------------------------------------------------
agents:
  - id: ticket_watcher
    type: system
    implementation:
      type: webhook_listener_service  # Rails service in app/services/pipeline/
      polling_interval: 60s
      job_class: TicketWatcherJob  # SolidQueue background job
    role: listens for new or updated tickets from MCP clients
    triggers:
      - jira.issue_created
      - devops.workitem_created
    outputs:
      - ticket.intake
    error_handling:
      retry_count: 3
      fallback: manual_intake
      solidqueue_retry: true

  - id: clarifier
    type: ai
    implementation:
      type: aws_bedrock
      model: claude-3-5-haiku-20241022  # Fast, cost-effective for clarification
      temperature: 0.7
      max_tokens: 4000
      context_management:
        max_context: 100000
        history_retention: last_5_interactions
    role: generates clarification questions, validates requirements
    inputs:
      - ticket.intake
    outputs:
      - ticket.needs_clarification
      - ticket.clarified
    communication:
      adapters:  # Notification adapter pattern
        - slack  # SlackNotifier service
        - teams  # TeamsNotifier service
        - email  # EmailNotifier service (Mailgun)
      channels:
        - jira_comments  # Post to JIRA ticket
        - devops_comments  # Post to Azure DevOps work item
    artifacts:
      storage: PipelineArtifact model
      types:
        - clarifications.md
        - requirements_checklist.yaml
    human_gate:
      timeout_minutes: 120
      escalation: manager
      interaction_model: PipelineInteraction

  - id: planner
    type: ai
    implementation:
      type: aws_bedrock
      model: claude-sonnet-4-5-20250929  # Best reasoning for planning
      temperature: 0.5
      workspace:
        path: /tmp/pipeline-{execution_id}/planner
        cleanup: after_completion
        permissions: 0700
    role: builds implementation plan and acceptance tests
    inputs:
      - ticket.clarified
    outputs:
      - plan.ready
    artifacts:
      - plan.md
      - acceptance_tests.yaml
      - architecture_diagram.mermaid
    validation:
      min_test_cases: 3
      requires_rollback_plan: true

  - id: coder
    type: ai
    implementation:
      type: aws_bedrock
      model: claude-sonnet-4-5-20250929  # Best coding capabilities
      temperature: 0.3
      max_tokens: 8000
      workspace:
        path: /tmp/pipeline-{execution_id}/coder
        cleanup: after_completion
        permissions: 0700
        git_enabled: true
      tools_enabled:
        - file_operations
        - terminal_commands
        - web_search
        - git_operations
    role: generates code and unit tests, opens PR
    inputs:
      - plan.ready
    outputs:
      - pr.opened
    artifacts:
      - build.log
      - test_report.json
      - coverage.json
    tools:
      - repo
      - build
      - test
      - formatter
      - docgen
    constraints:
      max_pr_size_lines: 500
      min_test_coverage: 80
      required_files:
        - README.md
        - unit_tests
        - integration_tests

  - id: reviewer
    type: ai
    implementation:
      type: aws_bedrock
      model: claude-3-5-sonnet-20241022  # Cost-effective, great analysis
      temperature: 0.2
      max_tokens: 8000
      checklist_mode: true
    role: performs static analysis and review on PRs
    inputs:
      - pr.opened
    outputs:
      - pr.review.ready
      - pr.approved
      - pr.needs_changes
    artifacts:
      - review_report.md
      - gate.json
      - security_scan.json
    tools:
      - linter
      - static_sec
      - dep_scan
      - coverage
      - arch_rules
      - sonarqube
    review_criteria:
      - no_secrets
      - no_known_vulnerabilities
      - follows_patterns
      - has_tests
      - documentation_updated

  - id: cua_pack
    type: ai
    implementation:
      type: synthetic_tester
      parallel_execution: true
    role: runs synthetic user tests on environments
    inputs:
      - dev.merge
      - staging.promoted
    outputs:
      - cua.dev_passed
      - cua.staging_passed
      - cua.failed
    artifacts:
      - cua_report.json
      - screenshots/
      - videos/
      - performance_metrics.json
    tools:
      - playwright
      - api_tester
      - load_tester
      - lighthouse
    test_scenarios:
      - happy_path
      - edge_cases
      - negative_testing
      - load_testing
      - accessibility

  - id: release_manager
    type: system
    implementation:
      type: orchestrator
      deployment_tool: azure_devops
    role: promotes releases between environments under policy control
    inputs:
      - pr.approved
      - cua.dev_passed
      - cua.staging_passed
    outputs:
      - dev.merge
      - staging.promoted
      - prod.promoted
    policies:
      - opa.gates
      - security_scan
      - coverage_thresholds
      - change_window_compliance
    rollout_strategy:
      type: blue_green
      canary_percentage: 10
      health_check_interval: 60s

# ------------------------------------------------------------
#  MCP CLIENTS
# ------------------------------------------------------------
mcp_clients:
  - id: jira_mcp
    implementation: custom
    server_path: ./mcp-servers/jira
    source: jira
    capabilities:
      - read_issues
      - write_comments
      - transition_states
      - attach_files
    rate_limits:
      requests_per_minute: 60
      burst_limit: 100
    inbound_events:
      - issue_created -> ticket.intake
      - issue_updated -> ticket.updated
      - issue_commented -> ticket.comment
    outbound_commands:
      - ticket.comment
      - ticket.transition
      - ticket.attach
    auth: 
      type: oauth2
      token_refresh: automatic
    mapping:
      issue_fields:
        id: key
        title: fields.summary
        description: fields.description
        labels: fields.labels
        status: fields.status.name
        assignee: fields.assignee.displayName
        url: self
        priority: fields.priority.name
        story_points: fields.customfield_10001

  - id: devops_mcp
    implementation: custom
    server_path: ./mcp-servers/azure-devops
    source: azure_devops
    capabilities:
      - read_workitems
      - write_comments
      - create_pr
      - trigger_pipeline
    rate_limits:
      requests_per_minute: 100
    inbound_events:
      - workitem_created -> ticket.intake
      - workitem_updated -> ticket.updated
      - pullrequest_created -> pr.opened
      - build_completed -> cicd.status
    outbound_commands:
      - ticket.comment
      - workitem.transition
      - pr.comment
      - pipeline.trigger
    auth: 
      type: service_principal
      vault: azure_keyvault
    mapping:
      workitem_fields:
        id: id
        title: fields['System.Title']
        description: fields['System.Description']
        status: fields['System.State']
        assignee: fields['System.AssignedTo']
        url: url
        area_path: fields['System.AreaPath']

# ------------------------------------------------------------
#  VERSION CONTROL
# ------------------------------------------------------------
version_control:
  strategy: gitflow
  providers:
    - github  # Support for GitHub repositories
    - azure_repos  # Support for Azure Repos
  branches:
    main: main
    develop: develop
    feature: feature/{ticket_id}-{description}
    release: release/{version}
    hotfix: hotfix/{ticket_id}
  pr_requirements:
    - all_tests_pass
    - code_review_approved
    - no_merge_conflicts
    - signed_commits
    - linear_history
  commit_convention: conventional  # feat:, fix:, docs:, etc.
  auto_merge:
    enabled: true
    conditions:
      - all_checks_passed
      - approved_by >= 1
      - no_requested_changes

# ------------------------------------------------------------
#  TESTING STRATEGY
# ------------------------------------------------------------
testing:
  unit:
    min_coverage: 80%
    frameworks: 
      - pytest  # Python
      - jest    # JavaScript
      - xunit   # .NET
      - go_test # Go
    mutation_testing: true
  integration:
    environments: [dev, staging]
    data_management: 
      strategy: synthetic
      pii_masking: true
    frameworks:
      - postman
      - rest_assured
  synthetic_user:
    tool: playwright
    browsers: [chrome, firefox, safari, edge]
    scenarios:
      happy_path:
        weight: 40%
        critical: true
      edge_cases:
        weight: 30%
      negative_testing:
        weight: 20%
      load_testing:
        weight: 10%
        users: 100
        ramp_up: 5m
  performance:
    tools: [lighthouse, k6]
    thresholds:
      response_time_p95: 2000ms
      error_rate: 0.1%
      throughput: 1000rps

# ------------------------------------------------------------
#  HUMAN GATES
# ------------------------------------------------------------
human_gates:
  - id: risky_changes
    trigger: policy.risky_surface_block
    paths:
      - "^auth/"
      - "^billing/"
      - "^infra/"
      - "^migrations/"
    notification:
      channels: [slack, email, teams]
      sla_minutes: 120
      escalation_after: 240
    approval_requirements:
      min_approvers: 2
      eligible_approvers: [senior_devs, managers, security_team]
      require_different_teams: true

  - id: production_deploy
    trigger: staging.ready_for_prod
    notification:
      channels: [slack, pagerduty]
    approval_requirements:
      min_approvers: 1
      eligible_approvers: [release_managers, oncall_engineers]
      blackout_windows:
        - friday_after_3pm
        - holidays
        - scheduled_maintenance

# ------------------------------------------------------------
#  SECURITY
# ------------------------------------------------------------
security:
  secrets_management:
    provider: azure_keyvault
    rotation_policy: 90_days
    detection:
      - trufflehog
      - git_secrets
  code_scanning:
    sast:
      tools: [sonarqube, semgrep]
      gate_on_critical: true
      gate_on_high: false
    sca:
      tools: [snyk, dependabot]
      auto_update_patches: true
    container_scanning:
      tools: [trivy, azure_defender]
  runtime:
    waf: azure_front_door
    ddos_protection: true
    api_rate_limiting: true
  audit:
    log_all_state_transitions: true
    compliance: [SOC2, HIPAA]
    retention_days: 365
    immutable_storage: true

# ------------------------------------------------------------
#  EVENT SCHEMA
# ------------------------------------------------------------
events:
  - name: ticket.intake
    schema_version: 1.0
    payload:
      ticket_id: string
      title: string
      description: string
      labels: [string]
      status: string
      priority: enum[critical, high, medium, low]
      url: string
      source_system: enum[jira, azure_devops]
      custom_fields: dict
      estimated_effort: number
      deadline: datetime

  - name: pr.opened
    schema_version: 1.0
    payload:
      ticket_id: string
      pr_id: string
      pr_url: string
      branch: string
      base_branch: string
      repo: string
      files_changed: number
      lines_added: number
      lines_deleted: number

  - name: cua.dev_passed
    schema_version: 1.0
    payload:
      env: dev
      report_url: string
      summary: string
      status: enum[passed, failed, flaky]
      test_results:
        passed: number
        failed: number
        skipped: number
      performance_metrics:
        response_time_p50: number
        response_time_p95: number
        error_rate: float

# ------------------------------------------------------------
#  STATE MACHINE
# ------------------------------------------------------------
states:
  - NEW
  - CLARIFYING
  - PLANNING
  - IMPLEMENTING
  - REVIEW
  - TESTING
  - DEV
  - STAGING
  - AWAITING_PROD_APPROVAL
  - PROD
  - DONE
  - FAILED
  - ROLLED_BACK

transitions:
  - from: NEW
    to: CLARIFYING
    on: ticket.intake
  - from: CLARIFYING
    to: PLANNING
    on: ticket.clarified
  - from: PLANNING
    to: IMPLEMENTING
    on: plan.ready
  - from: IMPLEMENTING
    to: REVIEW
    on: pr.opened
  - from: REVIEW
    to: TESTING
    on: pr.approved
  - from: REVIEW
    to: IMPLEMENTING
    on: pr.needs_changes
  - from: TESTING
    to: DEV
    on: tests.passed
  - from: DEV
    to: STAGING
    on: cua.dev_passed
  - from: STAGING
    to: AWAITING_PROD_APPROVAL
    on: cua.staging_passed
  - from: AWAITING_PROD_APPROVAL
    to: PROD
    on: human.approved
  - from: PROD
    to: DONE
    on: prod.promoted
  - from: PROD
    to: ROLLED_BACK
    on: rollback.triggered
  - any: FAILED
    on_error: true

# ------------------------------------------------------------
#  POLICY RULES (OPA)
# ------------------------------------------------------------
policies:
  - id: safe_auto_merge
    language: rego
    rule: |
      allow_auto_merge = true {
        input.changed_files_only_match(["*.md", "*.txt", "test/**"])
        input.secrets_scan_clean == true
        input.coverage_delta >= 0
        input.pr_size < 200
      }

  - id: risky_surface_block
    language: rego
    rule: |
      require_human_approval = true {
        input.changed_files_match(["^auth/", "^billing/", "^infra/", "^migrations/"])
      }

  - id: deployment_window
    language: rego
    rule: |
      allow_production_deploy = true {
        current_hour >= 9
        current_hour <= 17
        current_day_of_week != "Friday"
        not is_holiday(current_date)
      }

# ------------------------------------------------------------
#  ENVIRONMENTS
# ------------------------------------------------------------
environments:
  - name: dev
    type: ephemeral
    ci_pipeline: github_actions
    auto_deploy: true
    ttl: 24h
    resources:
      cpu: 2
      memory: 4Gi
      replicas: 1

  - name: staging
    type: persistent
    promotion_policy: 
      requires:
        - cua.dev_passed
        - opa.gates_passed
        - security_scan_passed
    refresh_data: nightly
    resources:
      cpu: 4
      memory: 8Gi
      replicas: 2

  - name: prod
    type: progressive
    promotion_policy:
      requires:
        - cua.staging_passed
        - human_approval
        - deployment_window
    rollout_strategy: 
      type: canary
      stages:
        - percentage: 10
          duration: 30m
        - percentage: 50
          duration: 2h
        - percentage: 100
    rollback_on_failure: 
      enabled: true
      triggers:
        - error_rate > 5%
        - response_time_p95 > 3000ms
        - health_check_fails > 3
    resources:
      cpu: 8
      memory: 16Gi
      replicas: 10
      autoscaling:
        min: 5
        max: 20
        target_cpu: 70%

# ------------------------------------------------------------
#  ROLLBACK MECHANISM
# ------------------------------------------------------------
rollback:
  trigger_conditions:
    - metric: error_rate
      threshold: 5%
      window: 5m
    - metric: response_time_p95
      threshold: 2000ms
      window: 5m
    - metric: health_check
      consecutive_failures: 3
  strategy:
    type: blue_green
    data_migration_compatible: true
    state_preservation: true
  notification:
    channels: [pagerduty, slack]
    include_metrics: true
  post_rollback:
    create_incident: true
    block_pipeline: true
    require_rca: true

# ------------------------------------------------------------
#  OBSERVABILITY
# ------------------------------------------------------------
observability:
  metrics:
    provider: azure_app_insights
    custom_metrics:
      - cycle_time
      - ai_token_usage
      - test_pass_rate
      - deployment_frequency
      - mttr
      - change_failure_rate
    dashboards:
      - overview
      - ai_performance
      - deployment_metrics
      - error_tracking
  logging:
    aggregator: azure_log_analytics
    retention_days: 30
    structured_logging: true
    pii_scrubbing: true
    log_levels:
      production: info
      staging: debug
      dev: trace
  tracing:
    provider: application_insights
    sample_rate: 0.1
    always_sample_errors: true
  alerts:
    - name: pipeline_stuck
      condition: state == FAILED for > 30min
      severity: high
      action: notify_oncall
    - name: high_ai_spend
      condition: ai_token_usage > daily_limit * 0.8
      severity: medium
      action: notify_manager
    - name: deployment_failure
      condition: deployment_failed_count > 2 in 1h
      severity: critical
      action: page_oncall

# ------------------------------------------------------------
#  RESOURCE MANAGEMENT
# ------------------------------------------------------------
resources:
  limits:
    concurrent_ai_agents: 5
    max_pr_size_lines: 500
    max_execution_time_minutes: 30
    max_tokens_per_ticket: 50000
  quotas:
    ai_tokens_per_day: 1000000
    deployments_per_day: 20
    test_runs_per_pr: 5
  cost_controls:
    alert_threshold_daily: 500
    hard_limit_daily: 1000
    shutdown_on_limit: false

# ------------------------------------------------------------
#  CONTINUOUS IMPROVEMENT
# ------------------------------------------------------------
continuous_improvement:
  metrics_collection:
    - false_positive_reviews
    - bug_escape_rate
    - ai_suggestion_acceptance_rate
    - mean_time_to_resolution
    - customer_reported_issues
  model_fine_tuning:
    frequency: monthly
    dataset: completed_tickets
    success_criteria:
      - acceptance_rate > 85%
      - bug_escape_rate < 5%
  feedback_loops:
    - source: pr_reviews
      target: reviewer_agent
    - source: production_incidents
      target: testing_strategy
    - source: clarification_rounds
      target: clarifier_agent
  reporting:
    frequency: weekly
    recipients: [engineering_managers, product_owners]
    format: markdown
    include:
      - velocity_trends
      - quality_metrics
      - ai_effectiveness
      - cost_analysis

# ------------------------------------------------------------
#  COMMUNICATION
# ------------------------------------------------------------
communication:
  - slack_mcp:
      workspace: company.slack.com
      purpose: clarifier questions, status updates
      channels:
        clarifications: "#ai-clarifications"
        status: "#ai-pipeline-status"
        alerts: "#ai-pipeline-alerts"
      threads_per_ticket: true
      noise_control: minimal
      rate_limit: 10_per_minute

  - teams:
      purpose: human approvals
      channels:
        approvals: "Production Approvals"

  - email:
      purpose: audit_trail
      recipients:
        on_failure: [oncall@company.com]
        on_success: [releases@company.com]

# ------------------------------------------------------------
#  DATABASE SCHEMA
# ------------------------------------------------------------
database:
  tables:
    mcp_connections:
      description: Stores credentials and config for JIRA, DevOps, GitHub, Azure Repos
      fields:
        - entity_id: reference to tenant
        - system_type: enum[jira, azure_devops, github, azure_repos]
        - name: user-friendly name
        - encrypted_config: encrypted credentials and settings
        - status: enum[active, inactive, error]
        - metadata: JSONB (org, project, repo filters)
        - last_sync_at: timestamp

    pipeline_executions:
      description: Main state tracker for each ticket being processed
      fields:
        - entity_id: reference to tenant
        - mcp_connection_id: source ticket system
        - ticket_id: ticket identifier
        - ticket_system: enum[jira, azure_devops]
        - ticket_url: link to original ticket
        - ticket_title: ticket summary
        - ticket_description: full description
        - priority: enum[critical, high, medium, low]
        - ticket_metadata: JSONB (custom fields, labels, etc)
        - git_connection_id: reference to GitHub/Azure Repos connection
        - repository: repo identifier
        - branch_name: feature branch created
        - pr_id: pull request number
        - pr_url: link to PR
        - status: enum[NEW, CLARIFYING, PLANNING, IMPLEMENTING, REVIEW, TESTING, DEV, STAGING, AWAITING_PROD_APPROVAL, PROD, DONE, FAILED, ROLLED_BACK]
        - state_history: JSONB array of state transitions
        - state_changed_at: timestamp
        - total_tokens_used: integer
        - total_cost: decimal
        - started_at: timestamp
        - completed_at: timestamp

    agent_executions:
      description: Tracks individual agent runs within a pipeline execution
      fields:
        - pipeline_execution_id: parent execution
        - agent_id: enum[clarifier, planner, coder, reviewer, cua_pack]
        - status: enum[pending, running, completed, failed]
        - workspace_path: isolated /tmp directory
        - inputs: JSONB input data
        - outputs: JSONB results
        - logs: text execution logs
        - error_message: text error details
        - tokens_used: integer
        - cost: decimal
        - started_at: timestamp
        - completed_at: timestamp

    pipeline_artifacts:
      description: Stores generated files (plans, reports, code)
      fields:
        - pipeline_execution_id: parent execution
        - agent_execution_id: which agent created it
        - artifact_type: enum[plan, test_spec, review_report, code, screenshot]
        - file_name: string
        - content: text (if < 100KB)
        - storage_path: S3 path (if large)
        - file_size: integer
        - metadata: JSONB

    pipeline_events:
      description: Event bus and audit trail
      fields:
        - pipeline_execution_id: parent execution
        - event_type: string (ticket.intake, pr.opened, etc)
        - payload: JSONB event data
        - source: string (jira, github, agent, human)
        - processed: boolean

    pipeline_interactions:
      description: Human interactions (clarifications, approvals)
      fields:
        - pipeline_execution_id: parent execution
        - user_id: who responded
        - interaction_type: enum[clarification, approval, rejection]
        - channel: enum[slack, teams, email]
        - external_thread_id: Slack/Teams message ID
        - question: text
        - response: text
        - status: enum[pending, answered, timeout]
        - asked_at: timestamp
        - answered_at: timestamp
        - timeout_at: timestamp

# ------------------------------------------------------------
#  COST ANALYSIS
# ------------------------------------------------------------
cost_analysis:
  ai_models:
    claude_sonnet_4_5:
      input: $7.50 per 1M tokens
      output: $15.00 per 1M tokens
      use_cases: [planner, coder]
    claude_3_5_sonnet:
      input: $3.00 per 1M tokens
      output: $15.00 per 1M tokens
      use_cases: [reviewer]
    claude_3_5_haiku:
      input: $1.00 per 1M tokens
      output: $5.00 per 1M tokens
      use_cases: [clarifier]

  estimated_cost_per_ticket:
    clarifier: $0.02  # ~2K tokens @ Haiku
    planner: $0.15    # ~5K tokens @ Sonnet 4.5
    coder: $0.75      # ~10K tokens @ Sonnet 4.5
    reviewer: $0.24   # ~8K tokens @ Sonnet 3.5
    total: $1.16 per ticket

  monthly_projections:
    tickets_per_day: 10
    working_days: 22
    monthly_tickets: 220
    monthly_ai_cost: $255
    infrastructure: $300
    total_monthly: $555

# ------------------------------------------------------------
#  AMOS INTEGRATION
# ------------------------------------------------------------
amos_integration:
  description: >
    This pipeline extends the existing AMOS platform by adding autonomous
    development capabilities. It reuses existing infrastructure and patterns.

  reused_components:
    bedrock_service:
      file: app/services/bedrock_service.rb
      usage: All AI agents use BedrockService for Claude API calls
      features:
        - Model abstraction
        - Tool calling support
        - Token usage tracking
        - Prompt caching support

    solid_queue:
      usage: All async agent execution via SolidQueue
      queues:
        - pipeline (priority 10)
        - agents (priority 8)
        - notifications (priority 6)
      jobs:
        - ProcessPipelineJob
        - AgentExecutionJob
        - CleanupWorkspacesJob

    entity_scoping:
      pattern: All pipeline models belong_to :entity
      concerns: Include EntityScoped in controllers
      usage: Multi-tenant isolation for pipeline executions

    integration_system:
      models: [Integration, Connection, IntegrationOperation, IntegrationLog]
      usage: MCP connections stored as Connection records
      pattern: Reuse encrypted_credentials pattern

    workflow_system:
      similarity: Pipeline states similar to WorkflowExecution
      models: [WorkflowContext, TaskSession]
      pattern: PipelineExecution mirrors WorkflowExecution design

    tools_pattern:
      base_class: BaseTool
      catalog: Tools::ToolCatalog
      new_tools:
        - Tools::GitOperationsTool
        - Tools::CodeReviewTool
        - Tools::TestRunnerTool

  new_components:
    services:
      - Pipeline::Orchestrator  # State machine coordinator
      - Pipeline::StateMachine  # State transition logic
      - MCP::JiraClient  # JIRA REST API wrapper
      - MCP::AzureDevOpsClient  # Azure DevOps API
      - Git::GithubClient  # GitHub API operations
      - Git::AzureReposClient  # Azure Repos API
      - Agents::ClarifierAgent  # Question generation
      - Agents::PlannerAgent  # Implementation planning
      - Agents::CoderAgent  # Code generation
      - Agents::ReviewerAgent  # Code review
      - Agents::WorkspaceManager  # /tmp isolation
      - Notifiers::SlackNotifier  # Slack messages
      - Notifiers::TeamsNotifier  # Teams notifications
      - Notifiers::EmailNotifier  # Email via Mailgun

    models:
      - MCPConnection  # Credentials for external systems
      - PipelineExecution  # Main state tracker
      - AgentExecution  # Individual agent runs
      - PipelineArtifact  # Generated files
      - PipelineEvent  # Event bus + audit
      - PipelineInteraction  # Human Q&A

    controllers:
      - Admin::PipelineConnectionsController  # MCP setup UI
      - Admin::PipelineExecutionsController  # Pipeline dashboard
      - Api::PipelineWebhooksController  # JIRA/DevOps webhooks

    jobs:
      - ProcessPipelineJob  # Main orchestration
      - AgentExecutionJob  # Run individual agents
      - TicketWatcherJob  # Poll for new tickets
      - CleanupWorkspacesJob  # /tmp cleanup
      - SyncTicketSystemsJob  # Periodic sync
      - HealthCheckConnectionsJob  # Connection health

  ui_additions:
    admin_sidebar:
      section: "Dev Pipeline"
      links:
        - MCP Connections (JIRA, DevOps, GitHub, Azure)
        - Pipeline Executions (list view)
        - Agent Performance (metrics dashboard)
        - Cost Tracking (AI spend)

    scout_integration:
      description: Pipeline status visible in Scout chat
      examples:
        - "What tickets are in progress?"
        - "Show me pipeline execution for JIRA-123"
        - "Retry failed pipeline for DEV-456"
      tools:
        - get_pipeline_status
        - retry_pipeline_execution
        - list_active_pipelines