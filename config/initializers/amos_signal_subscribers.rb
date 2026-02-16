# frozen_string_literal: true

# Subscribe to ActiveSupport::Notifications to emit AMOS signals
#
# These subscribers convert existing notification events into signals
# that AMOS's autonomous loop can respond to.

Rails.application.config.after_initialize do
  # Resource limit warnings → AMOS signal
  ActiveSupport::Notifications.subscribe('resource.limit_warning') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    entity_id = event.payload[:entity_id]
    next unless entity_id

    entity = Entity.find_by(id: entity_id)
    next unless entity

    AmosSignalMonitor.emit!(
      entity: entity,
      signal_type: 'resource_limit_warning',
      source: 'resource_manager',
      strength: 0.6,
      summary: "Resource limit warning: #{event.payload[:resource_type]} at #{event.payload[:usage_pct]}%",
      data: event.payload.slice(:resource_type, :usage_pct, :current, :limit)
    )
  rescue => e
    Rails.logger.debug "[AmosSignalSubscriber] resource.limit_warning failed: #{e.message}"
  end

  # Resource limit breach → Critical AMOS signal
  ActiveSupport::Notifications.subscribe('resource.limit_breach') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    entity_id = event.payload[:entity_id]
    next unless entity_id

    entity = Entity.find_by(id: entity_id)
    next unless entity

    AmosSignalMonitor.emit!(
      entity: entity,
      signal_type: 'resource_limit_warning',
      source: 'resource_manager',
      strength: 0.9, # Critical — near-immediate trigger
      summary: "RESOURCE LIMIT BREACH: #{event.payload[:resource_type]}",
      data: event.payload.slice(:resource_type, :usage_pct, :current, :limit)
    )
  rescue => e
    Rails.logger.debug "[AmosSignalSubscriber] resource.limit_breach failed: #{e.message}"
  end

  # Token limit exceeded → AMOS awareness
  ActiveSupport::Notifications.subscribe('tokens.user_limit_exceeded') do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    entity_id = event.payload[:entity_id]
    next unless entity_id

    entity = Entity.find_by(id: entity_id)
    next unless entity

    AmosSignalMonitor.emit!(
      entity: entity,
      signal_type: 'resource_limit_warning',
      source: 'resource_manager',
      strength: 0.5,
      summary: "User token limit exceeded: #{event.payload[:user_id]}",
      data: event.payload.slice(:user_id, :tokens_used, :limit)
    )
  rescue => e
    Rails.logger.debug "[AmosSignalSubscriber] tokens.user_limit_exceeded failed: #{e.message}"
  end
end
