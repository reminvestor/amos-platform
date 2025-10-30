class TicketWatcherJob < ApplicationJob
  queue_as :pipeline

  def perform
    Rails.logger.info "👀 Checking for new tickets..."

    # Get all active ticket system connections
    ticket_connections = McpConnection.active_connections.ticket_systems

    ticket_connections.each do |connection|
      check_connection_for_tickets(connection)
    end
  rescue => e
    Rails.logger.error "Ticket watcher failed: #{e.message}"
  end

  private

  def check_connection_for_tickets(connection)
    client = connection.client

    # Fetch recent tickets (last 10 minutes)
    tickets = client.fetch_recent_tickets(since: 10.minutes.ago)

    tickets.each do |ticket|
      # Check if we already have a pipeline execution for this ticket
      existing = PipelineExecution.find_by(
        entity: connection.entity,
        mcp_connection: connection,
        ticket_id: ticket[:id]
      )

      next if existing

      # FILTERING: Skip tickets that aren't ready for AI development
      unless ticket_ready_for_pipeline?(ticket, connection)
        Rails.logger.info "⏭️  Skipping ticket #{ticket[:id]}: Not ready for AI pipeline"
        next
      end

      # Create new pipeline execution
      pipeline = PipelineExecution.create!(
        entity: connection.entity,
        mcp_connection: connection,
        ticket_id: ticket[:id],
        ticket_system: connection.system_type,
        ticket_url: ticket[:url],
        ticket_title: ticket[:title],
        ticket_description: ticket[:description],
        priority: map_priority(ticket[:priority]),
        ticket_metadata: ticket[:metadata] || {}
      )

      Rails.logger.info "📋 Created pipeline execution #{pipeline.id} for ticket #{ticket[:id]}"

      # Start processing
      ProcessPipelineJob.perform_later(pipeline.id)
    end
  rescue => e
    Rails.logger.error "Failed to check #{connection.name}: #{e.message}"
    connection.mark_unhealthy!(e.message)
  end

  # Determine if a ticket is ready for AI pipeline processing
  def ticket_ready_for_pipeline?(ticket, connection)
    # Get filtering configuration from connection metadata
    config = connection.metadata&.dig('pipeline_filters') || default_pipeline_filters

    # Strategy 1: Status-based filtering (most common)
    return false unless status_matches?(ticket[:status], config['allowed_statuses'])

    # Strategy 2: Label-based filtering (opt-in approach)
    if config['require_label'].present?
      return false unless has_required_label?(ticket[:labels], config['require_label'])
    end

    # Strategy 3: Issue type filtering (skip epics, subtasks, etc.)
    return false unless issue_type_allowed?(ticket[:issue_type], config['allowed_issue_types'])

    # Strategy 4: Component filtering (only specific components)
    if config['allowed_components'].present?
      return false unless component_matches?(ticket[:components], config['allowed_components'])
    end

    # Strategy 5: Custom field filtering (e.g., "Ready for AI" checkbox)
    if config['custom_field_check'].present?
      field_name = config['custom_field_check']['field']
      expected_value = config['custom_field_check']['value']
      return false unless custom_field_matches?(ticket, field_name, expected_value)
    end

    # Strategy 6: Exclude tickets with blocking labels
    if config['exclude_labels'].present?
      return false if has_blocking_label?(ticket[:labels], config['exclude_labels'])
    end

    # Strategy 7: Assignee check (only unassigned or assigned to AI bot)
    if config['assignee_filter'].present?
      return false unless assignee_matches?(ticket[:assignee], config['assignee_filter'])
    end

    # All filters passed
    true
  end

  # Check if ticket status is in allowed list
  def status_matches?(status, allowed_statuses)
    return true if allowed_statuses.blank?  # No filtering if not configured

    allowed_statuses.any? { |allowed| status&.downcase&.include?(allowed.downcase) }
  end

  # Check if ticket has required label
  def has_required_label?(labels, required_label)
    return false if labels.blank?

    labels.any? { |label| label.downcase == required_label.downcase }
  end

  # Check if issue type is allowed
  def issue_type_allowed?(issue_type, allowed_types)
    return true if allowed_types.blank?  # No filtering if not configured

    allowed_types.any? { |allowed| issue_type&.downcase == allowed.downcase }
  end

  # Check if component matches allowed list
  def component_matches?(components, allowed_components)
    return false if components.blank?

    allowed_components.any? { |allowed| components.include?(allowed) }
  end

  # Check custom field value
  def custom_field_matches?(ticket, field_name, expected_value)
    custom_fields = ticket[:custom_fields] || ticket[:metadata] || {}
    actual_value = custom_fields[field_name]

    case expected_value
    when TrueClass, FalseClass
      actual_value == expected_value
    when String
      actual_value&.to_s&.downcase == expected_value.downcase
    else
      actual_value == expected_value
    end
  end

  # Check if ticket has any blocking labels
  def has_blocking_label?(labels, exclude_labels)
    return false if labels.blank? || exclude_labels.blank?

    labels.any? { |label| exclude_labels.any? { |excluded| label.downcase.include?(excluded.downcase) } }
  end

  # Check assignee filter
  def assignee_matches?(assignee, filter)
    case filter
    when 'unassigned'
      assignee.blank?
    when 'any'
      true
    else
      assignee&.downcase&.include?(filter.downcase)
    end
  end

  # Default filtering configuration
  def default_pipeline_filters
    {
      # Only pick up tickets in these statuses
      'allowed_statuses' => [
        'Ready for Development',
        'Ready for Dev',
        'To Do',
        'Selected for Development'
      ],

      # Optionally require a specific label (comment out to disable)
      # 'require_label' => 'ai-pipeline',

      # Only these issue types
      'allowed_issue_types' => [
        'Story',
        'Task',
        'Feature',
        'Enhancement'
      ],

      # Exclude tickets with these labels
      'exclude_labels' => [
        'blocked',
        'on-hold',
        'needs-discussion',
        'manual-only',
        'no-ai'
      ],

      # Assignee filter: 'unassigned', 'any', or specific username
      'assignee_filter' => 'unassigned'
    }
  end

  def map_priority(priority_str)
    case priority_str&.downcase
    when 'critical', 'blocker', 'highest'
      :critical
    when 'high', 'major'
      :high
    when 'medium', 'normal'
      :medium
    else
      :low
    end
  end
end
