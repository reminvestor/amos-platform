# SystemSetting model for managing system-level configuration and API keys
#
# Stores sensitive API keys and system configuration with encryption support.
# Supports reading from ENV variables as fallback.
#
# Usage:
#   SystemSetting.get("OPENAI_API_KEY")           # Returns decrypted value
#   SystemSetting.set("OPENAI_API_KEY", "sk-...") # Encrypts and stores
class SystemSetting < ApplicationRecord
  # Validations
  validates :key, presence: true, uniqueness: true
  validates :category, presence: true

  # Scopes
  scope :by_category, ->(category) { where(category: category) }
  scope :sensitive, -> { where(is_sensitive: true) }
  scope :non_sensitive, -> { where(is_sensitive: false) }

  # Categories
  CATEGORIES = {
    ai: "AI Services",
    voice: "Voice Assistant",
    integrations: "Third-party Integrations",
    infrastructure: "Infrastructure",
    email: "Email Services"
  }.freeze

  # Encrypt sensitive values before saving
  before_save :encrypt_sensitive_value, if: :is_sensitive?

  # Get a system setting value (decrypted if sensitive)
  def self.get(key, default = nil)
    setting = find_by(key: key)
    return default unless setting

    setting.is_sensitive? ? setting.decrypted_value : setting.value
  end

  # Set a system setting value
  def self.set(key, value, **options)
    setting = find_or_initialize_by(key: key)
    setting.value = value
    setting.category ||= options[:category]
    setting.description ||= options[:description]
    setting.is_sensitive = options[:is_sensitive] if options.key?(:is_sensitive)
    setting.last_updated_by = options[:updated_by]
    setting.save!
    setting
  end

  # Get decrypted value for sensitive settings
  def decrypted_value
    return value unless is_sensitive?
    return nil if encrypted_value.blank?

    decrypt(encrypted_value)
  end

  # Get masked value for display (shows only first/last chars)
  def masked_value
    val = is_sensitive? ? decrypted_value : value
    return nil if val.blank?
    return val if val.length < 8

    "#{val[0..3]}...#{val[-4..-1]}"
  end

  # Check if setting is using ENV fallback
  def using_env_fallback?
    value.blank? && encrypted_value.blank? && ENV[key].present?
  end

  # Get effective value (DB value or ENV fallback)
  def effective_value
    (is_sensitive? ? decrypted_value : value) || ENV[key]
  end

  # Seed default system settings from ENV
  def self.seed_defaults!
    # AI Services
    set("OPENAI_API_KEY", ENV["OPENAI_API_KEY"] || "",
        category: "ai", description: "OpenAI API key for GPT models and embeddings", is_sensitive: true)
    set("OPENAI_EMBEDDING_MODEL", ENV["OPENAI_EMBEDDING_MODEL"] || "text-embedding-ada-002",
        category: "ai", description: "OpenAI embedding model for RAG", is_sensitive: false)

    # AWS/Bedrock
    set("AWS_ACCESS_KEY_ID", ENV["AWS_ACCESS_KEY_ID"] || "",
        category: "ai", description: "AWS Access Key for Bedrock (Claude) and Polly", is_sensitive: true)
    set("AWS_SECRET_ACCESS_KEY", ENV["AWS_SECRET_ACCESS_KEY"] || "",
        category: "ai", description: "AWS Secret Access Key", is_sensitive: true)
    set("AWS_REGION", ENV["AWS_REGION"] || "us-east-1",
        category: "ai", description: "AWS region for services", is_sensitive: false)

    # Voice Assistant
    set("DEEPGRAM_API_KEY", ENV["DEEPGRAM_API_KEY"] || "",
        category: "voice", description: "Deepgram API key for speech-to-text", is_sensitive: true)
    set("DEEPGRAM_WEBHOOK_SECRET", ENV["DEEPGRAM_WEBHOOK_SECRET"] || "",
        category: "voice", description: "Deepgram webhook signature secret", is_sensitive: true)

    # Third-party Integrations
    set("GITHUB_TOKEN", ENV["GITHUB_TOKEN"] || "",
        category: "integrations", description: "GitHub personal access token for MCP server", is_sensitive: true)
    set("TRELLO_API_KEY", ENV["TRELLO_API_KEY"] || "",
        category: "integrations", description: "Trello API key for MCP server", is_sensitive: true)
    set("TRELLO_API_TOKEN", ENV["TRELLO_API_TOKEN"] || "",
        category: "integrations", description: "Trello API token for MCP server", is_sensitive: true)

    # Email Services
    set("MAILGUN_API_KEY", ENV["MAILGUN_API_KEY"] || "",
        category: "email", description: "Mailgun API key for sending emails", is_sensitive: true)
    set("MAILGUN_DOMAIN", ENV["MAILGUN_DOMAIN"] || "",
        category: "email", description: "Mailgun domain for email sending", is_sensitive: false)

    # Infrastructure
    set("REDIS_URL", ENV["REDIS_URL"] || "redis://redis:6379/0",
        category: "infrastructure", description: "Redis connection URL", is_sensitive: false)
    set("DATABASE_URL", ENV["DATABASE_URL"] || "",
        category: "infrastructure", description: "PostgreSQL database connection URL", is_sensitive: true)
  end

  private

  # Simple encryption (in production, use Rails encrypted credentials or vault)
  def encrypt(value)
    return nil if value.blank?
    Base64.strict_encode64(value.reverse) # Simple obfuscation
  end

  def decrypt(encrypted)
    return nil if encrypted.blank?
    Base64.strict_decode64(encrypted).reverse
  end

  def encrypt_sensitive_value
    self.encrypted_value = encrypt(value) if value.present?
    self.value = nil # Clear plaintext for sensitive settings
  end
end
