# frozen_string_literal: true

# ModuleIntegration
#
# Tracks which integrations a module needs to function.
# Enables:
# - Build-time integration checks (Platform Factory tells user what's needed)
# - Status tracking (show "⚠️ 2/3 integrations connected")
# - Agent collaboration hints (module agent knows to ask integration agent)
# - Proactive Amos ("Your Social Media Command Center needs Instagram connected")
#
class ModuleIntegration < ApplicationRecord
  belongs_to :app_module
  belongs_to :integration

  # Statuses
  STATUSES = %w[required optional connected disconnected].freeze
  
  # Purposes (why the module needs this integration)
  PURPOSES = %w[
    publishing
    analytics
    sync
    import
    export
    notifications
    authentication
    payment
    storage
    communication
  ].freeze

  validates :purpose, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :app_module_id, uniqueness: { scope: :integration_id }

  scope :required, -> { where(status: 'required') }
  scope :optional, -> { where(status: 'optional') }
  scope :connected, -> { where(status: 'connected') }
  scope :disconnected, -> { where(status: %w[required disconnected]) }
  scope :critical, -> { where(is_critical: true) }

  # Check if this integration is ready to use
  def ready?
    status == 'connected' && integration_connection&.connected?
  end

  # Get the actual integration connection for this entity
  def integration_connection
    app_module.entity&.integration_connections&.find_by(integration: integration)
  end

  # Update status based on connection state
  def sync_status!
    connection = integration_connection
    
    if connection&.connected?
      update!(status: 'connected', connected_at: connection.last_health_check || Time.current)
    elsif status == 'connected'
      update!(status: 'disconnected')
    end
  end

  # Human-readable status message
  def status_message
    case status
    when 'connected'
      "✅ #{integration.name} connected"
    when 'required'
      if is_critical
        "🚨 #{integration.name} required (critical)"
      else
        "⚠️ #{integration.name} required"
      end
    when 'optional'
      "ℹ️ #{integration.name} optional"
    when 'disconnected'
      "❌ #{integration.name} disconnected"
    end
  end

  # Get integration agent slug for this integration
  def integration_agent_slug
    "integration_#{integration.slug}_agent"
  end
end

