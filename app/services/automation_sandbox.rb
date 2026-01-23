# frozen_string_literal: true

# AutomationSandbox - Safely executes AI-generated automation code
#
# The sandbox:
# - Wraps code in a controlled execution environment
# - Enforces a timeout to prevent infinite loops
# - Limits output size to prevent memory issues
# - Provides only the safe helpers from AutomationContext
# - Catches and reports errors gracefully
#
class AutomationSandbox
  TIMEOUT_SECONDS = 10
  MAX_OUTPUT_SIZE = 1_000_000  # 1MB

  attr_reader :code, :trigger_data, :context

  def initialize(automation:, trigger_data:, user: nil)
    @automation = automation
    @code = automation.code
    @trigger_data = trigger_data.with_indifferent_access
    @context = AutomationContext.new(
      automation: automation,
      trigger_data: trigger_data,
      user: user
    )
  end

  # Execute the automation code and return the result
  def execute
    return error_result("No code provided") if code.blank?

    start_time = Time.current
    result = nil

    begin
      # Wrap the code in a controlled execution environment
      Timeout.timeout(TIMEOUT_SECONDS) do
        result = execute_in_sandbox
      end
    rescue Timeout::Error
      return error_result("Execution timed out after #{TIMEOUT_SECONDS} seconds")
    rescue SecurityError => e
      return error_result("Security violation: #{e.message}")
    rescue => e
      Rails.logger.error "[AutomationSandbox] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      return error_result(e.message)
    end

    duration_ms = ((Time.current - start_time) * 1000).round(2)

    # Validate the result
    validate_and_wrap_result(result, duration_ms)
  end

  private

  # Patterns that indicate dangerous code
  DANGEROUS_PATTERNS = [
    /\bFile\b/,                    # File system access
    /\bDir\b/,                     # Directory access
    /\bIO\b/,                      # IO operations
    /\bOpen3\b/,                   # Process spawning
    /\bsystem\s*\(/,               # System commands
    /\b`[^`]+`/,                   # Backtick commands
    /\bexec\s*\(/,                 # Exec
    /\bspawn\s*\(/,                # Spawn
    /\bfork\s*\{/,                 # Fork
    /\bKernel\s*\.\s*system/,      # Kernel.system
    /\bKernel\s*\.\s*exec/,        # Kernel.exec
    /\beval\s*\(/,                 # Eval (prevent nested eval)
    /\brequire\s+/,                # Require
    /\brequire_relative\s+/,       # Require relative
    /\bload\s+/,                   # Load
    /\bENV\s*\[/,                  # ENV access
    /\b__FILE__\b/,                # File path
    /\b__dir__\b/,                 # Directory path
    /\bBinding\b/,                 # Binding access
    /\bObjectSpace\b/,             # ObjectSpace
    /\bGC\b/,                      # Garbage collector
    /\bProcess\b/,                 # Process control
    /\bThread\b/,                  # Threading
    /\bSocket\b/,                  # Direct socket access
    /\bTCPSocket\b/,               # TCP sockets
    /\bUDPSocket\b/,               # UDP sockets
    /\bNet::HTTP\b/,               # Net::HTTP (use http_get/post instead)
  ].freeze

  def execute_in_sandbox
    # Security check: scan for dangerous patterns
    validate_code_safety!(@code)
    
    # Create a sandbox environment with all helpers
    env = SandboxEnvironment.new(@context, @trigger_data)
    
    # Evaluate the user code in the environment's binding
    # The code defines execute(trigger_data) which we then call
    env.instance_eval(@code, "(automation:#{@automation.id || 'new'})", 1)
    
    # Now call the execute method
    env.execute(@trigger_data)
  end

  def validate_code_safety!(code)
    DANGEROUS_PATTERNS.each do |pattern|
      if code.match?(pattern)
        matched = code.match(pattern)
        raise SecurityError, "Forbidden pattern detected: #{matched[0].truncate(30)}"
      end
    end
  end

  def validate_and_wrap_result(result, duration_ms)
    # Handle nil result
    result = { success: true, message: "Completed" } if result.nil?

    # Ensure it's a hash
    unless result.is_a?(Hash)
      result = { success: true, data: result }
    end

    # Check output size
    if result.to_json.bytesize > MAX_OUTPUT_SIZE
      return error_result("Output too large (max #{MAX_OUTPUT_SIZE / 1_000_000}MB)")
    end

    # Normalize the result
    {
      success: result[:success] != false,
      data: result.except(:success, :error),
      message: result[:message],
      duration_ms: duration_ms
    }
  end

  def error_result(message)
    {
      success: false,
      error: message,
      data: nil,
      duration_ms: nil
    }
  end

  # Inner class that provides the execution environment
  # All helper methods are directly available to user code
  class SandboxEnvironment
    def initialize(context, trigger_data)
      @context = context
      @trigger_data = trigger_data.with_indifferent_access
    end

    # Make trigger_data available
    attr_reader :trigger_data

    # ============================================
    # DATA OPERATIONS
    # ============================================

    def record
      @context.record
    end

    def changes
      @context.changes
    end

    def find_record(id)
      @context.find_record(id)
    end

    def query_records(conditions = {}, **opts)
      @context.query_records(conditions, **opts)
    end

    def count_records(conditions = {})
      @context.count_records(conditions)
    end

    def create_record(attributes)
      @context.create_record(attributes)
    end

    def update_record(id, attributes)
      @context.update_record(id, attributes)
    end

    # ============================================
    # NOTIFICATIONS
    # ============================================

    def send_email(**args)
      @context.send_email(**args)
    end

    def send_slack_message(**args)
      @context.send_slack_message(**args)
    end

    def notify_user(**args)
      @context.notify_user(**args)
    end

    def notify_role(**args)
      @context.notify_role(**args)
    end

    # ============================================
    # HTTP
    # ============================================

    def http_get(url, **args)
      @context.http_get(url, **args)
    end

    def http_post(url, **args)
      @context.http_post(url, **args)
    end

    # ============================================
    # DATE/TIME
    # ============================================

    def now
      @context.now
    end

    def today
      @context.today
    end

    def days_from_now(n)
      @context.days_from_now(n)
    end

    def days_ago(n)
      @context.days_ago(n)
    end

    def beginning_of_day(date = nil)
      @context.beginning_of_day(date || today)
    end

    def end_of_day(date = nil)
      @context.end_of_day(date || today)
    end

    def parse_date(str)
      @context.parse_date(str)
    end

    def parse_datetime(str)
      @context.parse_datetime(str)
    end

    def format_date(date, format = '%B %d, %Y')
      @context.format_date(date, format)
    end

    def format_time(time, format = '%I:%M %p')
      @context.format_time(time, format)
    end

    # ============================================
    # STRING HELPERS
    # ============================================

    def titleize(str)
      @context.titleize(str)
    end

    def downcase(str)
      @context.downcase(str)
    end

    def upcase(str)
      @context.upcase(str)
    end

    def strip(str)
      @context.strip(str)
    end

    def truncate(str, length, **opts)
      @context.truncate(str, length, **opts)
    end

    def slugify(str)
      @context.slugify(str)
    end

    def pluralize(count, singular, plural = nil)
      @context.pluralize(count, singular, plural)
    end

    # ============================================
    # NUMBER HELPERS
    # ============================================

    def format_currency(cents, **opts)
      @context.format_currency(cents, **opts)
    end

    def to_cents(dollars)
      @context.to_cents(dollars)
    end

    def to_dollars(cents)
      @context.to_dollars(cents)
    end

    def round(num, decimals = 2)
      @context.round(num, decimals)
    end

    def format_number(num, **opts)
      @context.format_number(num, **opts)
    end

    def format_percentage(num, **opts)
      @context.format_percentage(num, **opts)
    end

    # ============================================
    # CONDITIONAL HELPERS
    # ============================================

    def present?(val)
      @context.present?(val)
    end

    def blank?(val)
      @context.blank?(val)
    end

    def default(val, fallback)
      @context.default(val, fallback)
    end

    def if_else(condition, true_val, false_val)
      @context.if_else(condition, true_val, false_val)
    end

    # ============================================
    # ARRAY/HASH HELPERS
    # ============================================

    def first(arr)
      @context.first(arr)
    end

    def last(arr)
      @context.last(arr)
    end

    def join(arr, sep = ', ')
      @context.join(arr, sep)
    end

    def split(str, sep = ',')
      @context.split(str, sep)
    end

    def get(obj, path)
      @context.get(obj, path)
    end

    def merge(*hashes)
      @context.merge(*hashes)
    end

    # ============================================
    # LOOKUP HELPERS
    # ============================================

    def lookup_user_by_email(email)
      @context.lookup_user_by_email(email)
    end

    def lookup_contact_by_email(email)
      @context.lookup_contact_by_email(email)
    end

    def get_user(user_id)
      @context.get_user(user_id)
    end

    # ============================================
    # LOGGING
    # ============================================

    def log(message)
      @context.log(message)
    end

    def debug(message)
      @context.debug(message)
    end
  end
end
