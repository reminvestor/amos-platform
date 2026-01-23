# frozen_string_literal: true

# ExecutionGuardService - Ensures AI jobs complete and don't get stuck
#
# PROBLEMS IT SOLVES:
# 1. AI says "I'll do X" but doesn't call the tool
# 2. Tool chains break in the middle (A → B fails, C never runs)
# 3. Execution hangs with no response
# 4. AI loops on the same failing call
# 5. Chained delegations never return
#
# STRATEGIES:
# - Intent Detection: Parse response for unfulfilled promises
# - Chain Tracking: Monitor multi-step operations
# - Watchdog: Timeout hung executions
# - Force Execution: Re-prompt to actually call tools
# - Loop Detection: Break infinite retry loops
#
class ExecutionGuardService
  # Patterns that indicate the AI intends to do something
  INTENT_PATTERNS = [
    /I'll\s+(now\s+)?(fetch|retrieve|get|pull|load|show|display|call|execute|run|check)/i,
    /I\s+will\s+(now\s+)?(fetch|retrieve|get|pull|load|show|display|call|execute|run|check)/i,
    /Let\s+me\s+(now\s+)?(fetch|retrieve|get|pull|load|show|display|call|execute|run|check)/i,
    /I'm\s+going\s+to\s+(fetch|retrieve|get|pull|load|show|display|call|execute|run|check)/i,
    /I'm\s+(now\s+)?(fetching|retrieving|getting|pulling|loading|showing|displaying|calling|executing|running|checking)/i,
    /Fetching\s+(the|your|this)/i,
    /Retrieving\s+(the|your|this)/i,
    /Loading\s+(the|your|this)/i,
    /Calling\s+(the|your|this)/i,
    /Executing\s+(the|your|this)/i,
  ].freeze

  # Patterns that indicate a chain/sequence
  CHAIN_PATTERNS = [
    /then\s+(I'll|I\s+will|let\s+me)/i,
    /first.*then/i,
    /step\s+\d+.*step\s+\d+/i,
    /after\s+that/i,
    /next,?\s+I/i,
    /finally,?\s+I/i,
    /I'll\s+display\s+both/i,
    /side.by.side/i,
  ].freeze

  # Known tool mappings for intent -> tool
  INTENT_TO_TOOL_MAPPING = {
    'fetch stripe' => 'execute_integration',
    'fetch quickbooks' => 'execute_integration',
    'get stripe' => 'execute_integration',
    'get quickbooks' => 'execute_integration',
    'pull stripe' => 'execute_integration',
    'pull quickbooks' => 'execute_integration',
    'p&l' => 'execute_integration',
    'profit and loss' => 'execute_integration',
    'display' => 'create_freeform_canvas',
    'show side' => 'create_freeform_canvas',
    'side by side' => 'create_freeform_canvas',
    'visualize' => 'create_freeform_canvas',
    'chart' => 'create_freeform_canvas',
    'graph' => 'create_freeform_canvas',
  }.freeze

  attr_reader :entity, :user, :session_id

  def initialize(entity:, user:, session_id: nil)
    @entity = entity
    @user = user
    @session_id = session_id
    @execution_state = ExecutionState.new
  end

  # ═══════════════════════════════════════════════════════════════
  # MAIN GUARDS
  # ═══════════════════════════════════════════════════════════════

  # Check if AI response contains unfulfilled intent (promise without action)
  # @param response [String] The AI's text response
  # @param tool_calls [Array] Tool calls made in this turn
  # @return [Hash] { has_unfulfilled_intent: bool, intents: [...], suggested_prompt: string }
  def check_unfulfilled_intent(response:, tool_calls: [])
    intents = detect_intents(response)
    
    return { has_unfulfilled_intent: false, intents: [] } if intents.empty?
    
    # Check if any intent was fulfilled by tool calls
    fulfilled_intents = intents.select { |intent| tool_fulfills_intent?(tool_calls, intent) }
    unfulfilled = intents - fulfilled_intents
    
    if unfulfilled.any?
      Rails.logger.warn "[ExecutionGuard] ⚠️ Unfulfilled intents detected: #{unfulfilled.join(', ')}"
      
      suggested_prompt = build_fulfillment_prompt(unfulfilled, response)
      
      {
        has_unfulfilled_intent: true,
        intents: unfulfilled,
        fulfilled: fulfilled_intents,
        suggested_prompt: suggested_prompt,
        force_tool_call: should_force_tool_call?(unfulfilled)
      }
    else
      { has_unfulfilled_intent: false, intents: intents, fulfilled: intents }
    end
  end

  # Track and validate a multi-step chain
  # @param chain_id [String] Unique ID for this chain
  # @param expected_steps [Array] List of expected tool calls
  # @return [ChainTracker] A tracker for this chain
  def track_chain(chain_id:, expected_steps: [])
    tracker = ChainTracker.new(
      id: chain_id,
      expected_steps: expected_steps,
      started_at: Time.current
    )
    
    @execution_state.register_chain(tracker)
    tracker
  end

  # Check if a chain is complete
  def chain_complete?(chain_id)
    tracker = @execution_state.get_chain(chain_id)
    return true unless tracker # No chain = complete
    
    tracker.complete?
  end

  # Get incomplete chains that may be stuck
  def stuck_chains(timeout_seconds: 60)
    @execution_state.chains.select do |chain|
      !chain.complete? && chain.age_seconds > timeout_seconds
    end
  end

  # Detect if we're in an infinite loop
  # @param recent_tool_calls [Array] Last N tool calls
  # @return [Hash] { is_loop: bool, pattern: string, break_suggestion: string }
  def detect_loop(recent_tool_calls:)
    return { is_loop: false } if recent_tool_calls.length < 3
    
    # Look for repeated patterns
    signatures = recent_tool_calls.map { |tc| tool_call_signature(tc) }
    
    # Check for direct repetition (A, A, A)
    if signatures.last(3).uniq.length == 1
      return {
        is_loop: true,
        pattern: :direct_repeat,
        repeated_call: signatures.last,
        break_suggestion: "STOP: You've called #{signatures.last} 3 times. The call is failing. " \
                         "Read the error message and try a different approach."
      }
    end
    
    # Check for ping-pong (A, B, A, B)
    if signatures.length >= 4
      last_4 = signatures.last(4)
      if last_4[0] == last_4[2] && last_4[1] == last_4[3]
        return {
          is_loop: true,
          pattern: :ping_pong,
          repeated_calls: [last_4[0], last_4[1]],
          break_suggestion: "STOP: You're alternating between #{last_4[0]} and #{last_4[1]}. " \
                           "This is an infinite loop. Take a different approach or ask the user for help."
        }
      end
    end
    
    { is_loop: false }
  end

  # Build a correction prompt when AI needs to actually execute
  # @param context [Hash] Current execution context
  # @return [String] Additional prompt to force execution
  def build_execution_reminder(context = {})
    unfulfilled = context[:unfulfilled_intents] || []
    
    reminder = <<~PROMPT
      
      ⚠️ EXECUTION REQUIRED:
      You stated you would perform actions but did not call the required tools.
      
      YOU MUST NOW CALL THE APPROPRIATE TOOLS. Do not just describe what you'll do - ACTUALLY DO IT.
      
    PROMPT
    
    if unfulfilled.any?
      reminder += "Unfulfilled actions: #{unfulfilled.join(', ')}\n\n"
    end
    
    if context[:suggested_tools]
      reminder += "Suggested tools: #{context[:suggested_tools].join(', ')}\n"
    end
    
    reminder
  end

  # ═══════════════════════════════════════════════════════════════
  # WATCHDOG
  # ═══════════════════════════════════════════════════════════════

  # Create a watchdog that will timeout if execution takes too long
  # @param timeout_seconds [Integer] Timeout in seconds
  # @param on_timeout [Proc] Callback when timeout occurs
  # @return [Watchdog] A watchdog instance
  def create_watchdog(timeout_seconds: 120, on_timeout: nil)
    Watchdog.new(
      timeout_seconds: timeout_seconds,
      on_timeout: on_timeout,
      guard_service: self
    )
  end

  private

  def detect_intents(response)
    intents = []
    
    INTENT_PATTERNS.each do |pattern|
      if match = response.match(pattern)
        # Extract the action verb
        action = match[0].downcase.gsub(/i'll|i will|let me|i'm going to|i'm|now/i, '').strip
        intents << action unless action.empty?
      end
    end
    
    # Also detect chains
    if CHAIN_PATTERNS.any? { |p| response.match?(p) }
      intents << '_chain_detected'
    end
    
    intents.uniq
  end

  def tool_fulfills_intent?(tool_calls, intent)
    return true if tool_calls.nil? || intent.nil?
    
    # Check if any tool call matches the intent
    tool_names = tool_calls.map { |tc| tc[:name] || tc['name'] }.compact
    
    # Direct tool name match
    return true if tool_names.any? { |name| intent.include?(name.gsub('_', ' ')) }
    
    # Intent to tool mapping match
    INTENT_TO_TOOL_MAPPING.each do |pattern, expected_tool|
      if intent.include?(pattern) && tool_names.include?(expected_tool)
        return true
      end
    end
    
    false
  end

  def should_force_tool_call?(unfulfilled_intents)
    # Force tool call if we have clear action intents
    action_intents = unfulfilled_intents.reject { |i| i == '_chain_detected' }
    action_intents.any?
  end

  def build_fulfillment_prompt(unfulfilled, original_response)
    # Identify what tools should be called
    suggested_tools = []
    
    unfulfilled.each do |intent|
      INTENT_TO_TOOL_MAPPING.each do |pattern, tool|
        if intent.downcase.include?(pattern)
          suggested_tools << tool
        end
      end
    end
    
    suggested_tools = suggested_tools.uniq
    
    prompt = "You said: \"#{original_response.truncate(200)}\"\n\n"
    prompt += "But you didn't call any tools. "
    
    if suggested_tools.any?
      prompt += "You should call: #{suggested_tools.join(', ')}\n"
    end
    
    prompt += "\nPlease execute the action now using the appropriate tool."
    prompt
  end

  def tool_call_signature(tool_call)
    name = tool_call[:name] || tool_call['name']
    # Create a simplified signature (tool name only for loop detection)
    name.to_s
  end

  # ═══════════════════════════════════════════════════════════════
  # INNER CLASSES
  # ═══════════════════════════════════════════════════════════════

  class ExecutionState
    attr_reader :chains

    def initialize
      @chains = []
      @mutex = Mutex.new
    end

    def register_chain(tracker)
      @mutex.synchronize { @chains << tracker }
    end

    def get_chain(chain_id)
      @mutex.synchronize { @chains.find { |c| c.id == chain_id } }
    end

    def cleanup_old_chains(max_age_seconds: 300)
      @mutex.synchronize do
        @chains.reject! { |c| c.age_seconds > max_age_seconds }
      end
    end
  end

  class ChainTracker
    attr_reader :id, :expected_steps, :completed_steps, :started_at

    def initialize(id:, expected_steps:, started_at:)
      @id = id
      @expected_steps = expected_steps
      @completed_steps = []
      @started_at = started_at
    end

    def mark_complete(step_name)
      @completed_steps << step_name unless @completed_steps.include?(step_name)
    end

    def complete?
      return true if expected_steps.empty?
      (expected_steps - completed_steps).empty?
    end

    def progress
      return 1.0 if expected_steps.empty?
      completed_steps.length.to_f / expected_steps.length
    end

    def age_seconds
      Time.current - started_at
    end

    def pending_steps
      expected_steps - completed_steps
    end
  end

  class Watchdog
    attr_reader :timeout_seconds, :started_at, :guard_service

    def initialize(timeout_seconds:, on_timeout:, guard_service:)
      @timeout_seconds = timeout_seconds
      @on_timeout = on_timeout
      @guard_service = guard_service
      @started_at = Time.current
      @completed = false
      @thread = nil
    end

    def start
      @started_at = Time.current
      @thread = Thread.new do
        sleep @timeout_seconds
        trigger_timeout unless @completed
      end
      self
    end

    def complete!
      @completed = true
      @thread&.kill
    end

    def elapsed_seconds
      Time.current - @started_at
    end

    def remaining_seconds
      [timeout_seconds - elapsed_seconds, 0].max
    end

    private

    def trigger_timeout
      Rails.logger.error "[ExecutionGuard] ⏰ Watchdog timeout after #{@timeout_seconds}s"
      @on_timeout&.call({
        timeout_seconds: @timeout_seconds,
        elapsed: elapsed_seconds
      })
    end
  end
end

