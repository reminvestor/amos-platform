# frozen_string_literal: true

# AutomationContext - Safe helpers available to automation code
#
# This provides a controlled set of operations that automation code
# can perform. Similar to TransformContext but for automations.
#
# All methods here are:
# - Rate-limited where appropriate
# - Entity-scoped (can't access other entities' data)
# - Logged for auditing
# - Safe from injection attacks
#
class AutomationContext
  attr_reader :entity, :web_app, :app_module, :user, :trigger_data, :automation

  def initialize(automation:, trigger_data: {}, user: nil)
    @automation = automation
    @entity = automation.entity
    @web_app = automation.web_app
    @app_module = automation.app_module
    @user = user
    @trigger_data = trigger_data.with_indifferent_access
    @allow_writes = true  # Can be disabled for dry-run testing
    @notifications_sent = 0
    @http_requests_made = 0
  end

  # ============================================
  # DATA OPERATIONS
  # ============================================

  # Get the record that triggered this automation
  def record
    trigger_data[:record]&.with_indifferent_access || {}
  end

  # Get the changes that triggered this automation (for update triggers)
  def changes
    trigger_data[:changes]&.with_indifferent_access || {}
  end

  # Find a record by ID
  def find_record(id)
    return nil unless app_module && id.present?
    
    model = dynamic_model
    return nil unless model
    
    record = model.find_by(id: id, entity_id: entity.id)
    record&.attributes&.with_indifferent_access
  end

  # Query records with conditions
  def query_records(conditions = {}, limit: 100, order: { created_at: :desc })
    return [] unless app_module

    model = dynamic_model
    return [] unless model

    model
      .where(entity_id: entity.id)
      .where(conditions)
      .order(order)
      .limit([limit, 100].min)  # Cap at 100
      .map { |r| r.attributes.with_indifferent_access }
  end

  # Count records matching conditions
  def count_records(conditions = {})
    return 0 unless app_module

    model = dynamic_model
    return 0 unless model

    model.where(entity_id: entity.id).where(conditions).count
  end

  # Create a new record (requires write permission)
  def create_record(attributes)
    raise "Write operations disabled" unless @allow_writes
    return { success: false, error: "No module configured" } unless app_module

    model = dynamic_model
    return { success: false, error: "Model not found" } unless model

    record = model.create!(
      attributes.merge(entity_id: entity.id, created_by_id: user&.id)
    )

    log("Created record: #{record.id}")
    { success: true, id: record.id, record: record.attributes }
  rescue => e
    { success: false, error: e.message }
  end

  # Update an existing record
  def update_record(id, attributes)
    raise "Write operations disabled" unless @allow_writes
    return { success: false, error: "No module configured" } unless app_module

    model = dynamic_model
    return { success: false, error: "Model not found" } unless model

    record = model.find_by(id: id, entity_id: entity.id)
    return { success: false, error: "Record not found" } unless record

    record.update!(attributes.merge(updated_by_id: user&.id))

    log("Updated record: #{id}")
    { success: true, id: record.id, record: record.attributes }
  rescue => e
    { success: false, error: e.message }
  end

  # ============================================
  # NOTIFICATIONS
  # ============================================

  MAX_NOTIFICATIONS_PER_EXECUTION = 10

  # Send an email
  def send_email(to:, subject:, body:, html: false)
    guard_notification_limit!

    AutomationMailer.custom_notification(
      to: to,
      subject: subject,
      body: body,
      html: html,
      entity: entity
    ).deliver_later

    log("Email sent to: #{to}")
    { success: true, message: "Email queued" }
  rescue => e
    { success: false, error: e.message }
  end

  # Send a Slack message
  def send_slack_message(channel:, message:, blocks: nil)
    guard_notification_limit!

    connection = entity.integration_connections.find_by(
      integration: Integration.find_by(slug: 'slack'),
      status: 'connected'
    )
    
    return { success: false, error: 'Slack not connected' } unless connection

    # Use the Slack integration to send
    result = SlackNotifier.new(connection).post(
      channel: channel,
      text: message,
      blocks: blocks
    )

    log("Slack message sent to: #{channel}")
    result
  rescue => e
    { success: false, error: e.message }
  end

  # Create a Hub notification
  def notify_user(user_id:, message:, type: 'info', action_url: nil)
    guard_notification_limit!

    notification = HubNotification.create!(
      entity: entity,
      user_id: user_id,
      message: message,
      notification_type: type,
      action_url: action_url,
      source: "automation:#{automation.id}"
    )

    log("Hub notification created for user: #{user_id}")
    { success: true, notification_id: notification.id }
  rescue => e
    { success: false, error: e.message }
  end

  # Notify all users with a specific role
  def notify_role(role:, message:, type: 'info')
    guard_notification_limit!

    users = entity.users.where(role: role)
    count = 0

    users.find_each do |u|
      HubNotification.create!(
        entity: entity,
        user_id: u.id,
        message: message,
        notification_type: type,
        source: "automation:#{automation.id}"
      )
      count += 1
    end

    log("Hub notifications sent to #{count} users with role: #{role}")
    { success: true, count: count }
  rescue => e
    { success: false, error: e.message }
  end

  # ============================================
  # HTTP REQUESTS (Allowlisted domains)
  # ============================================

  MAX_HTTP_REQUESTS_PER_EXECUTION = 5
  HTTP_TIMEOUT = 10  # seconds

  ALLOWED_DOMAINS = %w[
    api.stripe.com
    api.slack.com
    api.hubspot.com
    hooks.zapier.com
    api.sendgrid.com
    api.mailchimp.com
    api.twilio.com
  ].freeze

  def http_get(url, headers: {})
    guard_http_limit!
    validate_url!(url)

    response = HTTParty.get(url, headers: headers, timeout: HTTP_TIMEOUT)
    
    log("HTTP GET: #{url} -> #{response.code}")
    { success: response.success?, status: response.code, body: safe_parse_json(response.body) }
  rescue => e
    { success: false, error: e.message }
  end

  def http_post(url, body:, headers: {})
    guard_http_limit!
    validate_url!(url)

    default_headers = { 'Content-Type' => 'application/json' }
    response = HTTParty.post(
      url,
      body: body.is_a?(String) ? body : body.to_json,
      headers: default_headers.merge(headers),
      timeout: HTTP_TIMEOUT
    )

    log("HTTP POST: #{url} -> #{response.code}")
    { success: response.success?, status: response.code, body: safe_parse_json(response.body) }
  rescue => e
    { success: false, error: e.message }
  end

  # ============================================
  # DATE/TIME HELPERS
  # ============================================

  def now
    Time.current
  end

  def today
    Date.current
  end

  def days_from_now(n)
    n.days.from_now
  end

  def days_ago(n)
    n.days.ago
  end

  def beginning_of_day(date = today)
    date.beginning_of_day
  end

  def end_of_day(date = today)
    date.end_of_day
  end

  def parse_date(str)
    Date.parse(str.to_s)
  rescue
    nil
  end

  def parse_datetime(str)
    DateTime.parse(str.to_s)
  rescue
    nil
  end

  def format_date(date, format = '%B %d, %Y')
    date&.strftime(format)
  end

  def format_time(time, format = '%I:%M %p')
    time&.strftime(format)
  end

  # ============================================
  # STRING HELPERS
  # ============================================

  def titleize(str)
    str.to_s.titleize
  end

  def downcase(str)
    str.to_s.downcase
  end

  def upcase(str)
    str.to_s.upcase
  end

  def strip(str)
    str.to_s.strip
  end

  def truncate(str, length, omission: '...')
    str.to_s.truncate(length, omission: omission)
  end

  def slugify(str)
    str.to_s.parameterize
  end

  def pluralize(count, singular, plural = nil)
    count == 1 ? singular : (plural || singular.pluralize)
  end

  # ============================================
  # NUMBER/CURRENCY HELPERS
  # ============================================

  def format_currency(cents, currency: 'USD')
    ActionController::Base.helpers.number_to_currency(cents.to_f / 100, unit: currency_symbol(currency))
  end

  def to_cents(dollars)
    (dollars.to_f * 100).round.to_i
  end

  def to_dollars(cents)
    (cents.to_f / 100).round(2)
  end

  def round(num, decimals = 2)
    num.to_f.round(decimals)
  end

  def format_number(num, precision: 0)
    ActionController::Base.helpers.number_with_delimiter(num.round(precision))
  end

  def format_percentage(num, precision: 1)
    "#{num.round(precision)}%"
  end

  # ============================================
  # CONDITIONAL HELPERS
  # ============================================

  def present?(val)
    val.present?
  end

  def blank?(val)
    val.blank?
  end

  def default(val, fallback)
    val.present? ? val : fallback
  end

  def if_else(condition, true_val, false_val)
    condition ? true_val : false_val
  end

  # ============================================
  # ARRAY/HASH HELPERS
  # ============================================

  def first(arr)
    arr.is_a?(Array) ? arr.first : arr
  end

  def last(arr)
    arr.is_a?(Array) ? arr.last : arr
  end

  def join(arr, separator = ', ')
    arr.is_a?(Array) ? arr.join(separator) : arr.to_s
  end

  def split(str, separator = ',')
    str.to_s.split(separator).map(&:strip)
  end

  def get(obj, path)
    parts = path.to_s.split('.')
    value = obj
    parts.each do |p|
      value = value.is_a?(Hash) ? (value[p] || value[p.to_sym]) : nil
    end
    value
  end

  def merge(*hashes)
    hashes.reduce({}) { |acc, h| acc.merge(h || {}) }
  end

  # ============================================
  # LOOKUP HELPERS
  # ============================================

  def lookup_user_by_email(email)
    return nil if email.blank?
    entity.users.find_by(email: email.to_s.downcase)&.id
  end

  def lookup_contact_by_email(email)
    return nil if email.blank?
    entity.contacts.find_by(email: email.to_s.downcase)&.id
  end

  def get_user(user_id)
    return nil if user_id.blank?
    user = entity.users.find_by(id: user_id)
    user ? { id: user.id, email: user.email, name: user.full_name, role: user.role } : nil
  end

  # ============================================
  # LOGGING
  # ============================================

  def log(message)
    Rails.logger.info "[AutomationCode:#{automation.id}] #{message}"
  end

  def debug(message)
    Rails.logger.debug "[AutomationCode:#{automation.id}] #{message}"
  end

  # ============================================
  # PRIVATE HELPERS
  # ============================================

  private

  def dynamic_model
    return nil unless app_module

    model_code = app_module.module_code
    return nil unless model_code

    Modules::DynamicModelLoader.instance.get_model(model_code)
  end

  def guard_notification_limit!
    @notifications_sent += 1
    if @notifications_sent > MAX_NOTIFICATIONS_PER_EXECUTION
      raise "Notification limit exceeded (max #{MAX_NOTIFICATIONS_PER_EXECUTION} per execution)"
    end
  end

  def guard_http_limit!
    @http_requests_made += 1
    if @http_requests_made > MAX_HTTP_REQUESTS_PER_EXECUTION
      raise "HTTP request limit exceeded (max #{MAX_HTTP_REQUESTS_PER_EXECUTION} per execution)"
    end
  end

  def validate_url!(url)
    uri = URI.parse(url)
    
    unless uri.is_a?(URI::HTTPS)
      raise "Only HTTPS URLs are allowed"
    end

    # Check against allowlist plus any entity-configured domains
    allowed = ALLOWED_DOMAINS + (entity.settings['allowed_automation_domains'] || [])
    
    unless allowed.any? { |d| uri.host&.end_with?(d) }
      raise "Domain not allowed: #{uri.host}. Allowed: #{allowed.join(', ')}"
    end
  end

  def safe_parse_json(str)
    JSON.parse(str)
  rescue
    str
  end

  def currency_symbol(currency)
    case currency.to_s.upcase
    when 'USD' then '$'
    when 'EUR' then '€'
    when 'GBP' then '£'
    else '$'
    end
  end
end

