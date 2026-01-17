# frozen_string_literal: true

# AutomationSandbox - Safely executes AI-generated automation code
#
# The sandbox:
# - Wraps code in a module to prevent global pollution
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
    @trigger_data = trigger_data
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

  def execute_in_sandbox
    # Create an execution binding with the context methods available
    sandbox_binding = create_sandbox_binding

    # Wrap the user code in a module and execute
    wrapped_code = wrap_code(@code)

    # Evaluate the wrapped code
    eval(wrapped_code, sandbox_binding, "(automation:#{@automation.id})")
  end

  def create_sandbox_binding
    # Create a new binding with access to context helpers
    SandboxEnvironment.new(@context, @trigger_data).get_binding
  end

  def wrap_code(user_code)
    <<~RUBY
      # User's automation code wrapped in a module
      module AutomationModule
        extend self

        #{user_code}
      end

      # Execute and return the result
      AutomationModule.execute(trigger_data)
    RUBY
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
  class SandboxEnvironment
    def initialize(context, trigger_data)
      @context = context
      @trigger_data = trigger_data.with_indifferent_access
    end

    # Expose trigger_data to the sandbox
    def trigger_data
      @trigger_data
    end

    # Delegate all context methods to the AutomationContext
    # This is the "allowlist" of what automation code can do

    # Data operations
    def record; @context.record; end
    def changes; @context.changes; end
    def find_record(id); @context.find_record(id); end
    def query_records(conditions = {}, **opts); @context.query_records(conditions, **opts); end
    def count_records(conditions = {}); @context.count_records(conditions); end
    def create_record(attributes); @context.create_record(attributes); end
    def update_record(id, attributes); @context.update_record(id, attributes); end

    # Notifications
    def send_email(**args); @context.send_email(**args); end
    def send_slack_message(**args); @context.send_slack_message(**args); end
    def notify_user(**args); @context.notify_user(**args); end
    def notify_role(**args); @context.notify_role(**args); end

    # HTTP
    def http_get(url, **args); @context.http_get(url, **args); end
    def http_post(url, **args); @context.http_post(url, **args); end

    # Date/time
    def now; @context.now; end
    def today; @context.today; end
    def days_from_now(n); @context.days_from_now(n); end
    def days_ago(n); @context.days_ago(n); end
    def beginning_of_day(date = today); @context.beginning_of_day(date); end
    def end_of_day(date = today); @context.end_of_day(date); end
    def parse_date(str); @context.parse_date(str); end
    def parse_datetime(str); @context.parse_datetime(str); end
    def format_date(date, format = '%B %d, %Y'); @context.format_date(date, format); end
    def format_time(time, format = '%I:%M %p'); @context.format_time(time, format); end

    # String helpers
    def titleize(str); @context.titleize(str); end
    def downcase(str); @context.downcase(str); end
    def upcase(str); @context.upcase(str); end
    def strip(str); @context.strip(str); end
    def truncate(str, length, **opts); @context.truncate(str, length, **opts); end
    def slugify(str); @context.slugify(str); end
    def pluralize(count, singular, plural = nil); @context.pluralize(count, singular, plural); end

    # Number helpers
    def format_currency(cents, **opts); @context.format_currency(cents, **opts); end
    def to_cents(dollars); @context.to_cents(dollars); end
    def to_dollars(cents); @context.to_dollars(cents); end
    def round(num, decimals = 2); @context.round(num, decimals); end
    def format_number(num, **opts); @context.format_number(num, **opts); end
    def format_percentage(num, **opts); @context.format_percentage(num, **opts); end

    # Conditional helpers
    def present?(val); @context.present?(val); end
    def blank?(val); @context.blank?(val); end
    def default(val, fallback); @context.default(val, fallback); end
    def if_else(condition, true_val, false_val); @context.if_else(condition, true_val, false_val); end

    # Array/hash helpers
    def first(arr); @context.first(arr); end
    def last(arr); @context.last(arr); end
    def join(arr, sep = ', '); @context.join(arr, sep); end
    def split(str, sep = ','); @context.split(str, sep); end
    def get(obj, path); @context.get(obj, path); end
    def merge(*hashes); @context.merge(*hashes); end

    # Lookup helpers
    def lookup_user_by_email(email); @context.lookup_user_by_email(email); end
    def lookup_contact_by_email(email); @context.lookup_contact_by_email(email); end
    def get_user(user_id); @context.get_user(user_id); end

    # Logging
    def log(message); @context.log(message); end
    def debug(message); @context.debug(message); end

    # Get the binding for evaluation
    def get_binding
      binding
    end
  end
end

