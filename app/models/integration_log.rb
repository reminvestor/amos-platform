class IntegrationLog < ApplicationRecord
  include AmosSignalEmitter

  belongs_to :connection
  belongs_to :user, optional: true  # User may be nil for system/background operations
  belongs_to :scout_message, optional: true
  belongs_to :integration_operation, optional: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..) }
  scope :successful, -> { where("response_status < 400") }
  scope :failed, -> { where("response_status >= 400") }
  scope :for_entity, ->(entity) { joins(:connection).where(connections: { entity_id: entity.id }) }

  # Default values
  after_initialize :set_defaults, if: :new_record?

  # Callbacks
  before_save :sanitize_sensitive_data
  after_create :update_connection_health
  after_create :emit_integration_failure_signal

  def successful?
    response_status.present? && response_status < 400
  end

  def failed?
    !successful?
  end

  def rate_limited?
    response_status == 429
  end

  def execution_time_ms
    duration_ms || 0
  end

  def masked_request_headers
    mask_sensitive_headers(request_headers)
  end

  def masked_request_body
    redact_sensitive_fields(request_body)
  end

  def decrypted_response_body
    # Implement per-tenant decryption when needed
    # For now, return nil if encrypted
    return nil if response_body_encrypted.present?
    response_body
  end

  class << self
    def recent_for(entity, limit = 100)
      for_entity(entity).recent.limit(limit)
    end

    def group_by_hour(column = :created_at)
      # Sanitize column name to prevent SQL injection
      sanitized_column = ActiveRecord::Base.connection.quote_column_name(column)
      group("DATE_TRUNC('hour', #{sanitized_column})")
    end
  end

  private

  def set_defaults
    self.retry_count ||= 0
    self.dry_run ||= false
    self.metadata ||= {}
    self.request_headers ||= {}
    self.response_headers ||= {}
  end

  def sanitize_sensitive_data
    self.request_headers = mask_sensitive_headers(request_headers)
    self.request_body = redact_sensitive_fields(request_body)
    # Response body encryption would happen here if needed
  end

  def mask_sensitive_headers(headers)
    return {} if headers.blank?

    sensitive_headers = %w[
      authorization x-api-key api-key token
      x-auth-token cookie set-cookie
    ]

    headers.transform_keys(&:downcase).transform_values do |value|
      # Find the original key for this value
      original_key = headers.find { |k, v| v == value }&.first
      if original_key && sensitive_headers.include?(original_key.to_s.downcase)
        mask_value(value)
      else
        value
      end
    end
  end

  def redact_sensitive_fields(data, schema = nil)
    return data unless data.is_a?(Hash) || data.is_a?(Array)

    sensitive_patterns = /password|secret|token|key|ssn|sin|tax_id|card|cvv|account/i

    if data.is_a?(Array)
      return data.map { |item| redact_sensitive_fields(item, schema) }
    end

    data.each_with_object({}) do |(key, value), result|
      result[key] = if value.is_a?(String) && key.to_s.match?(sensitive_patterns)
        "[REDACTED]"
      elsif value.is_a?(Hash) || value.is_a?(Array)
        redact_sensitive_fields(value)
      else
        value
      end
    end
  end

  def mask_value(value)
    return value unless value.is_a?(String)
    return value if value.length < 8

    "#{value[0..3]}...#{value[-4..]}"
  end

  def update_connection_health
    # Update connection health status based on recent logs
    UpdateConnectionHealthJob.perform_later(connection) if failed?
  end

  def emit_integration_failure_signal
    return unless failed?

    # Only emit if there's a pattern of failures (checked via dedup)
    entity = connection&.entity
    return unless entity

    integration_name = connection&.integration&.name || 'unknown'

    emit_amos_signal!(
      signal_type: 'integration_failure_rate',
      source: 'integration_log',
      strength: rate_limited? ? 0.5 : 0.4,
      summary: "Integration failure: #{integration_name} (#{response_status})",
      data: {
        integration_name: integration_name,
        connection_id: connection_id,
        response_status: response_status,
        endpoint: endpoint
      }
    )
  end

  # Override entity resolution since IntegrationLog belongs_to connection, not entity
  def resolve_signal_entity
    connection&.entity
  end
end
