class McpConnection < ApplicationRecord
  # Multi-tenant scoping
  belongs_to :entity

  # Relationships
  has_many :pipeline_executions, dependent: :restrict_with_error
  has_many :pipeline_executions_as_git, class_name: 'PipelineExecution', foreign_key: 'git_connection_id', dependent: :restrict_with_error

  # Validations
  validates :system_type, presence: true, inclusion: { in: %w[jira azure_devops github azure_repos] }
  validates :name, presence: true
  validates :status, presence: true

  # Enums
  enum :status, {
    active: 0,
    inactive: 1,
    error: 2
  }, prefix: true

  # Scopes
  scope :active_connections, -> { where(status: :active) }
  scope :ticket_systems, -> { where(system_type: %w[jira azure_devops]) }
  scope :git_systems, -> { where(system_type: %w[github azure_repos]) }
  scope :recently_synced, -> { where('last_sync_at > ?', 1.hour.ago) }

  # Default values
  after_initialize :set_defaults, if: :new_record?

  # Getter/setter for config as hash (uses manual encryption below)
  def config
    return {} if encrypted_config.blank?
    JSON.parse(decrypt_config(encrypted_config)).deep_symbolize_keys
  rescue JSON::ParserError
    {}
  end

  def config=(value)
    self.encrypted_config = encrypt_config(value.to_json)
  end

  # Test connection health
  def test_connection!
    case system_type
    when 'jira'
      AiAgents::Mcp::JiraClient.new(self).test_connection
    when 'azure_devops'
      AiAgents::Mcp::AzureDevopsClient.new(self).test_connection
    when 'github'
      Git::GithubClient.new(self).test_connection
    when 'azure_repos'
      Git::AzureReposClient.new(self).test_connection
    else
      { success: false, error: "Unknown system type: #{system_type}" }
    end
  rescue => e
    Rails.logger.error "MCP connection test failed for #{name}: #{e.message}"
    status_error!
    { success: false, error: e.message }
  end

  # Update health check timestamp
  def mark_healthy!
    update!(
      status: :active,
      last_health_check_at: Time.current
    )
  end

  def mark_unhealthy!(error_message = nil)
    update!(
      status: :error,
      last_health_check_at: Time.current,
      metadata: metadata.merge(last_error: error_message, last_error_at: Time.current.iso8601)
    )
  end

  # Check if connection is a ticket system
  def ticket_system?
    %w[jira azure_devops].include?(system_type)
  end

  # Check if connection is a git system
  def git_system?
    %w[github azure_repos].include?(system_type)
  end

  # Get appropriate client instance
  def client
    case system_type
    when 'jira'
      AiAgents::Mcp::JiraClient.new(self)
    when 'azure_devops'
      AiAgents::Mcp::AzureDevopsClient.new(self)
    when 'github'
      Git::GithubClient.new(self)
    when 'azure_repos'
      Git::AzureReposClient.new(self)
    else
      raise "Unknown system type: #{system_type}"
    end
  end

  private

  def set_defaults
    self.status ||= :inactive
    self.metadata ||= {}
  end

  # Simple encryption/decryption (in production, use Rails encrypted credentials or AWS KMS)
  def encrypt_config(data)
    # Use Rails' built-in encryption
    crypt = ActiveSupport::MessageEncryptor.new(Rails.application.secret_key_base[0..31])
    crypt.encrypt_and_sign(data)
  end

  def decrypt_config(encrypted_data)
    crypt = ActiveSupport::MessageEncryptor.new(Rails.application.secret_key_base[0..31])
    crypt.decrypt_and_verify(encrypted_data)
  end
end
