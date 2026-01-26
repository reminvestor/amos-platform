# frozen_string_literal: true

require 'test_helper'

class AutomationSandboxTest < ActiveSupport::TestCase
  fixtures :entities, :users, :automation_codes

  setup do
    @entity = entities(:one)
    @user = users(:one)
    @automation = automation_codes(:simple_log_automation)
  end

  # ============================================
  # BASIC EXECUTION
  # ============================================

  test "executes simple code and returns result" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          { success: true, message: 'Hello from sandbox!' }
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    result = sandbox.execute

    assert result[:success]
    assert_equal 'Hello from sandbox!', result[:data][:message]
    assert result[:duration_ms].present?
  end

  test "can access trigger_data" do
    code_string = <<~'CODE'
      def execute(trigger_data)
        name = trigger_data[:record][:name]
        { success: true, message: "Hello, #{name}!" }
      end
    CODE

    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: code_string
    )

    sandbox = AutomationSandbox.new(
      automation: automation,
      trigger_data: { record: { name: 'World' } }
    )
    result = sandbox.execute

    assert result[:success]
    assert_equal 'Hello, World!', result[:data][:message]
  end

  test "can use record helper" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          { success: true, title: record[:title] }
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(
      automation: automation,
      trigger_data: { record: { title: 'Test Article' } }
    )
    result = sandbox.execute

    assert result[:success]
    assert_equal 'Test Article', result[:data][:title]
  end

  # ============================================
  # HELPER FUNCTIONS
  # ============================================

  test "string helpers work" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          {
            success: true,
            titleized: titleize('hello world'),
            upper: upcase('hello'),
            lower: downcase('HELLO'),
            stripped: strip('  hello  '),
            slug: slugify('Hello World!')
          }
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    result = sandbox.execute

    assert result[:success]
    assert_equal 'Hello World', result[:data][:titleized]
    assert_equal 'HELLO', result[:data][:upper]
    assert_equal 'hello', result[:data][:lower]
    assert_equal 'hello', result[:data][:stripped]
    assert_equal 'hello-world', result[:data][:slug]
  end

  test "date/time helpers work" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          {
            success: true,
            has_now: now.present?,
            has_today: today.present?,
            future: days_from_now(7).present?,
            past: days_ago(7).present?
          }
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    result = sandbox.execute

    assert result[:success]
    assert result[:data][:has_now]
    assert result[:data][:has_today]
    assert result[:data][:future]
    assert result[:data][:past]
  end

  test "number helpers work" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          {
            success: true,
            cents: to_cents(19.99),
            dollars: to_dollars(1999),
            rounded: round(3.14159, 2)
          }
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    result = sandbox.execute

    assert result[:success]
    assert_equal 1999, result[:data][:cents]
    assert_equal 19.99, result[:data][:dollars]
    assert_equal 3.14, result[:data][:rounded]
  end

  test "conditional helpers work" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          {
            success: true,
            is_present: present?('hello'),
            is_blank: blank?(nil),
            with_default: default(nil, 'fallback'),
            if_result: if_else(true, 'yes', 'no')
          }
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    result = sandbox.execute

    assert result[:success]
    assert result[:data][:is_present]
    assert result[:data][:is_blank]
    assert_equal 'fallback', result[:data][:with_default]
    assert_equal 'yes', result[:data][:if_result]
  end

  test "array/hash helpers work" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          arr = [1, 2, 3]
          hash = { a: { b: 'nested' } }
          
          {
            success: true,
            first_val: first(arr),
            last_val: last(arr),
            joined: join(arr, '-'),
            split_result: split('a,b,c', ','),
            nested: get(hash, 'a.b'),
            merged: merge({ a: 1 }, { b: 2 })
          }
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    result = sandbox.execute

    assert result[:success]
    assert_equal 1, result[:data][:first_val]
    assert_equal 3, result[:data][:last_val]
    assert_equal '1-2-3', result[:data][:joined]
    assert_equal ['a', 'b', 'c'], result[:data][:split_result]
    assert_equal 'nested', result[:data][:nested]
    assert_equal({ 'a' => 1, 'b' => 2 }, result[:data][:merged].stringify_keys)
  end

  test "log helper works" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          log("This is a test log message")
          { success: true, message: 'Logged' }
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    
    # Should not raise
    result = sandbox.execute
    assert result[:success]
  end

  # ============================================
  # ERROR HANDLING
  # ============================================

  test "handles missing code gracefully" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: nil
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    result = sandbox.execute

    assert_not result[:success]
    assert_equal 'No code provided', result[:error]
  end

  test "handles runtime errors gracefully" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          raise "Intentional error!"
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    result = sandbox.execute

    assert_not result[:success]
    assert_includes result[:error], 'Intentional error!'
  end

  test "handles nil return gracefully" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          nil
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    result = sandbox.execute

    assert result[:success]  # nil is treated as success
  end

  test "handles non-hash return" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          "just a string"
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    result = sandbox.execute

    assert result[:success]
    assert_equal 'just a string', result[:data][:data]
  end

  # ============================================
  # TIMEOUT PROTECTION
  # ============================================

  test "times out on infinite loops" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          loop { }  # Infinite loop
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    
    # Should timeout, not hang
    result = nil
    Timeout.timeout(15) do  # Give it a bit more than sandbox timeout
      result = sandbox.execute
    end

    assert_not result[:success]
    assert_includes result[:error], 'timed out'
  end

  # ============================================
  # SECURITY
  # ============================================

  test "cannot access File system" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          File.read('/etc/passwd')
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    result = sandbox.execute

    assert_not result[:success]
    # Should fail with undefined method or similar
  end

  test "cannot use require" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          require 'net/http'
          { success: true }
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    result = sandbox.execute

    # Should fail with security violation
    assert_not result[:success], "require should be blocked"
    assert result[:error].present?
  end

  test "cannot use system commands" do
    automation = AutomationCode.new(
      entity: @entity,
      name: 'Test',
      trigger_type: 'manual',
      code: <<~RUBY
        def execute(trigger_data)
          system('ls')
        end
      RUBY
    )

    sandbox = AutomationSandbox.new(automation: automation, trigger_data: {})
    result = sandbox.execute

    # Should fail with undefined method
    assert_not result[:success]
  end
end

