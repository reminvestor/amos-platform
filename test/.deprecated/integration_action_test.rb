# frozen_string_literal: true

require 'test_helper'

class IntegrationActionTest < ActiveSupport::TestCase
  fixtures :entities, :users, :integrations

  setup do
    @entity = entities(:one)
    @user = users(:one)
    
    # Find or create a test integration
    @integration = Integration.find_or_create_by!(
      slug: 'test_api',
      entity: nil
    ) do |i|
      i.name = 'Test API'
      i.api_base_url = 'https://api.test.com'
      i.auth_type = :api_key
      i.category = 'custom'
    end
    
    # Create a test operation
    @operation = @integration.integration_operations.find_or_create_by!(
      operation_id: 'test_api.create_item'
    ) do |op|
      op.name = 'Create Item'
      op.http_method = 'POST'
      op.path_template = '/items'
      op.description = 'Create a new item'
    end
    
    # Create a test action
    @action = IntegrationAction.create!(
      integration: @integration,
      integration_operation: @operation,
      action_name: 'create_item',
      description: 'Create a new test item',
      category: 'crud',
      input_schema: [
        { name: 'name', type: 'string', required: true, description: 'Item name' },
        { name: 'price', type: 'number', required: true, description: 'Price in dollars', min: 0 },
        { name: 'quantity', type: 'integer', required: false, description: 'Stock quantity' },
        { name: 'active', type: 'boolean', required: false }
      ],
      sample_input: { name: 'Test Item', price: 29.99 },
      mapping_code: <<~RUBY,
        def map(inputs)
          {
            item_name: titleize(inputs[:name]),
            price_cents: to_cents(inputs[:price]),
            stock: default(inputs[:quantity], 0),
            is_active: to_api_bool(default(inputs[:active], true), format: :string)
          }
        end
      RUBY
      status: :active
    )
  end

  # ============================================
  # MODEL TESTS
  # ============================================

  test 'creates action with valid attributes' do
    assert @action.persisted?
    assert_equal 'test_api.create_item', @action.slug
    assert @action.active?
  end

  test 'generates slug automatically' do
    action = IntegrationAction.new(
      integration: @integration,
      integration_operation: @operation,
      action_name: 'my_action',
      input_schema: []
    )
    action.valid?
    assert_equal 'test_api.my_action', action.slug
  end

  test 'validates required fields' do
    action = IntegrationAction.new
    assert_not action.valid?
    assert_includes action.errors[:action_name], "can't be blank"
    assert_includes action.errors[:input_schema], "can't be blank"
  end

  test 'enforces unique action_name per integration' do
    duplicate = IntegrationAction.new(
      integration: @integration,
      integration_operation: @operation,
      action_name: 'create_item',
      input_schema: []
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:action_name], 'has already been taken'
  end

  # ============================================
  # INPUT VALIDATION TESTS
  # ============================================

  test 'validates required inputs' do
    validation = @action.validate_inputs({})
    
    assert_not validation[:valid]
    assert_includes validation[:errors], 'name is required'
    assert_includes validation[:errors], 'price is required'
  end

  test 'validates with all required inputs' do
    validation = @action.validate_inputs({ name: 'Test', price: 10.00 })
    
    assert validation[:valid]
    assert_empty validation[:errors]
  end

  test 'validates number types' do
    validation = @action.validate_inputs({ name: 'Test', price: 'not_a_number' })
    
    assert_not validation[:valid]
    assert_includes validation[:errors], 'price must be a number'
  end

  test 'validates minimum values' do
    validation = @action.validate_inputs({ name: 'Test', price: -5 })
    
    assert_not validation[:valid]
    assert_includes validation[:errors], 'price must be >= 0'
  end

  test 'validates enum values' do
    action = IntegrationAction.create!(
      integration: @integration,
      integration_operation: @operation,
      action_name: 'enum_test',
      input_schema: [
        { name: 'status', type: 'enum', required: true, values: %w[active inactive] }
      ],
      status: :active
    )

    valid = action.validate_inputs({ status: 'active' })
    assert valid[:valid]

    invalid = action.validate_inputs({ status: 'unknown' })
    assert_not invalid[:valid]
    assert_includes invalid[:errors], 'status must be one of: active, inactive'
  end

  # ============================================
  # MAPPING CODE TESTS
  # ============================================

  test 'maps inputs using generated code' do
    result = @action.map_inputs({ name: 'widget', price: 29.99, quantity: 5, active: true })
    
    assert result[:success]
    assert_equal 'Widget', result[:params][:item_name]
    assert_equal 2999, result[:params][:price_cents]
    assert_equal 5, result[:params][:stock]
    assert_equal 'true', result[:params][:is_active]
  end

  test 'handles missing optional inputs with defaults' do
    result = @action.map_inputs({ name: 'widget', price: 10.00 })
    
    assert result[:success]
    assert_equal 0, result[:params][:stock]
    assert_equal 'true', result[:params][:is_active]
  end

  test 'falls back to pass-through without mapping code' do
    @action.update!(mapping_code: nil)
    
    inputs = { name: 'test', price: 10 }
    result = @action.map_inputs(inputs)
    
    assert result[:success]
    assert_equal 'test', result[:params][:name]
    assert_equal 10, result[:params][:price]
  end

  # ============================================
  # ACTION CONTEXT HELPER TESTS
  # ============================================

  test 'ActionContext string helpers work' do
    context = Integrations::ActionContext.new({ text: 'hello world' }, @integration, @action)
    
    assert_equal 'Hello World', context.titleize('hello world')
    assert_equal 'HELLO', context.upcase('hello')
    assert_equal 'hello', context.downcase('HELLO')
    assert_equal 'hello-world', context.slugify('Hello World')
    assert_equal 'helloWorld', context.camelize('hello_world')
  end

  test 'ActionContext number helpers work' do
    context = Integrations::ActionContext.new({}, @integration, @action)
    
    assert_equal 2999, context.to_cents(29.99)
    assert_equal 29.99, context.to_dollars(2999)
    assert_equal 3.14, context.round(3.14159, 2)
    assert_equal '0.00100000', context.to_string(0.001, 8)
  end

  test 'ActionContext trading pair normalization' do
    context = Integrations::ActionContext.new({}, @integration, @action)
    
    assert_equal 'BTC-USD', context.normalize_trading_pair('BTC/USD', :hyphen)
    assert_equal 'BTCUSD', context.normalize_trading_pair('BTC/USD', :concat)
    assert_equal 'BTC_USD', context.normalize_trading_pair('BTC-USD', :underscore)
  end

  test 'ActionContext API formatting helpers' do
    context = Integrations::ActionContext.new({}, @integration, @action)
    
    # Boolean formatting
    assert_equal 'true', context.to_api_bool(true, format: :string)
    assert_equal 1, context.to_api_bool(true, format: :integer)
    assert_equal 'no', context.to_api_bool(false, format: :yes_no)
    
    # Decimal formatting
    assert_equal '0.00100000', context.to_api_decimal(0.001, precision: 8)
    
    # Email normalization
    assert_equal 'test@example.com', context.normalize_email('  TEST@Example.COM  ')
  end

  test 'ActionContext conditional helpers' do
    context = Integrations::ActionContext.new({}, @integration, @action)
    
    assert context.present?('hello')
    assert_not context.present?(nil)
    assert context.blank?(nil)
    assert_equal 'default', context.default(nil, 'default')
    assert_equal 'value', context.default('value', 'default')
  end

  # ============================================
  # SANDBOX SECURITY TESTS
  # ============================================

  test 'sandbox times out on long-running code' do
    @action.update!(mapping_code: <<~RUBY)
      def map(inputs)
        sleep 10  # This should timeout
        {}
      end
    RUBY

    result = @action.map_inputs({ name: 'test', price: 10 })
    assert_not result[:success]
    assert_match(/timeout|timed out/i, result[:error])
  end

  test 'sandbox rejects invalid output' do
    @action.update!(mapping_code: <<~RUBY)
      def map(inputs)
        "not a hash"  # Must return a Hash
      end
    RUBY

    result = @action.map_inputs({ name: 'test', price: 10 })
    assert_not result[:success]
    assert_match(/must return a Hash/i, result[:error])
  end

  # ============================================
  # USAGE METRICS TESTS
  # ============================================

  test 'tracks success rate' do
    @action.update!(usage_count: 10, success_count: 8, error_count: 2)
    
    assert_equal 80.0, @action.success_rate
  end

  test 'success rate is 100% when unused' do
    @action.update!(usage_count: 0, success_count: 0)
    
    assert_equal 100.0, @action.success_rate
  end

  test 'returns required field names' do
    assert_equal %w[name price], @action.required_fields
  end

  test 'returns all field names' do
    assert_equal %w[name price quantity active], @action.input_field_names
  end
end

class ActionCodeExecutorTest < ActiveSupport::TestCase
  fixtures :integrations

  setup do
    @integration = Integration.find_or_create_by!(slug: 'executor_test') do |i|
      i.name = 'Executor Test'
      i.api_base_url = 'https://api.test.com'
      i.auth_type = :api_key
      i.category = 'custom'
    end
    
    @operation = @integration.integration_operations.find_or_create_by!(
      operation_id: 'executor_test.test_op'
    ) do |op|
      op.name = 'Test Op'
      op.http_method = 'POST'
      op.path_template = '/test'
    end
  end

  test 'executes mapping code and returns transformed params' do
    action = IntegrationAction.new(
      integration: @integration,
      integration_operation: @operation,
      mapping_code: <<~RUBY
        def map(inputs)
          {
            email: normalize_email(inputs[:email]),
            amount_cents: to_cents(inputs[:amount])
          }
        end
      RUBY
    )

    executor = Integrations::ActionCodeExecutor.new(action)
    result = executor.map_inputs({ email: '  USER@Example.COM  ', amount: 99.99 })

    assert result[:success]
    assert_equal 'user@example.com', result[:params][:email]
    assert_equal 9999, result[:params][:amount_cents]
  end

  test 'test_mapping returns detailed results' do
    action = IntegrationAction.new(
      integration: @integration,
      integration_operation: @operation,
      sample_input: { value: 100 },
      mapping_code: <<~RUBY
        def map(inputs)
          { doubled: inputs[:value] * 2 }
        end
      RUBY
    )

    executor = Integrations::ActionCodeExecutor.new(action)
    result = executor.test_mapping

    assert result[:success]
    assert_equal({ value: 100 }, result[:inputs])
    assert_equal 200, result[:output][:doubled]
    assert result[:duration_ms] > 0
  end
end

