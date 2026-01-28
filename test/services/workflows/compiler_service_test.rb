# frozen_string_literal: true

require "test_helper"

module Workflows
  class CompilerServiceTest < ActiveSupport::TestCase
    fixtures :users, :entities, :automation_codes

    def setup
      @entity = entities(:one)
      @user = users(:one)
    end

    # ============================================
    # BASIC COMPILATION
    # ============================================

    test "compiles simple manual trigger workflow" do
      automation = create_workflow({
        nodes: [
          { id: 'trigger-1', type: 'trigger-manual', x: 100, y: 100, config: {} },
          { id: 'success-1', type: 'output-success', x: 100, y: 300, config: {} }
        ],
        connections: [
          { from: 'trigger-1', to: 'success-1', fromPort: 'default', toPort: 'default' }
        ]
      })

      compiler = CompilerService.new(automation)
      result = compiler.compile!

      assert result[:success], "Compilation should succeed: #{result[:errors].join(', ')}"
      assert_equal 2, result[:compiled_steps].size
      assert_equal 'trigger-manual', result[:stats][:trigger_type]
      assert automation.reload.is_compiled?
    end

    test "compiles workflow with action nodes" do
      automation = create_workflow({
        nodes: [
          { id: 'trigger-1', type: 'trigger-manual', x: 100, y: 100, config: {} },
          { id: 'email-1', type: 'action-email', x: 100, y: 200, config: {
            to: 'test@example.com',
            subject: 'Test',
            body: 'Hello'
          }},
          { id: 'success-1', type: 'output-success', x: 100, y: 300, config: {} }
        ],
        connections: [
          { from: 'trigger-1', to: 'email-1', fromPort: 'default', toPort: 'default' },
          { from: 'email-1', to: 'success-1', fromPort: 'default', toPort: 'default' }
        ]
      })

      compiler = CompilerService.new(automation)
      result = compiler.compile!

      assert result[:success], "Compilation should succeed: #{result[:errors].join(', ')}"
      assert_equal 3, result[:compiled_steps].size
      
      email_step = result[:compiled_steps].find { |s| s['node_type'] == 'action-email' }
      assert_equal 'test@example.com', email_step['config']['to']
    end

    test "compiles workflow with conditional logic" do
      automation = create_workflow({
        nodes: [
          { id: 'trigger-1', type: 'trigger-manual', x: 100, y: 100, config: {} },
          { id: 'condition-1', type: 'logic-condition', x: 100, y: 200, config: {
            field: 'status',
            operator: 'equals',
            compare_to: 'active'
          }},
          { id: 'success-1', type: 'output-success', x: 0, y: 300, config: {} },
          { id: 'error-1', type: 'output-error', x: 200, y: 300, config: {} }
        ],
        connections: [
          { from: 'trigger-1', to: 'condition-1', fromPort: 'default', toPort: 'default' },
          { from: 'condition-1', to: 'success-1', fromPort: 'true', toPort: 'default' },
          { from: 'condition-1', to: 'error-1', fromPort: 'false', toPort: 'default' }
        ]
      })

      compiler = CompilerService.new(automation)
      result = compiler.compile!

      assert result[:success]
      
      condition_step = result[:compiled_steps].find { |s| s['node_type'] == 'logic-condition' }
      assert condition_step['conditions'].present?
      assert_equal 'if', condition_step['conditions']['type']
      assert_equal 'success-1', condition_step['conditions']['true_step']
      assert_equal 'error-1', condition_step['conditions']['false_step']
    end

    # ============================================
    # VALIDATION ERRORS
    # ============================================

    test "fails compilation without trigger node" do
      automation = create_workflow({
        nodes: [
          { id: 'email-1', type: 'action-email', x: 100, y: 200, config: { to: 'test@example.com' }},
          { id: 'success-1', type: 'output-success', x: 100, y: 300, config: {} }
        ],
        connections: [
          { from: 'email-1', to: 'success-1', fromPort: 'default', toPort: 'default' }
        ]
      })

      compiler = CompilerService.new(automation)
      result = compiler.compile!

      assert_not result[:success]
      assert result[:errors].any? { |e| e.include?('trigger') }
    end

    test "fails compilation with empty workflow" do
      automation = create_workflow({ nodes: [], connections: [] })

      compiler = CompilerService.new(automation)
      result = compiler.compile!

      assert_not result[:success]
      assert result[:errors].any? { |e| e.include?('No nodes') }
    end

    test "fails compilation without workflow definition" do
      automation = AutomationCode.create!(
        entity: @entity,
        created_by: @user,
        name: 'Empty Workflow',
        trigger_type: 'manual',
        code: '# empty',
        workflow_definition: nil
      )

      compiler = CompilerService.new(automation)
      result = compiler.compile!

      assert_not result[:success]
      assert result[:errors].any? { |e| e.include?('definition') }
    end

    test "detects circular dependencies" do
      automation = create_workflow({
        nodes: [
          { id: 'trigger-1', type: 'trigger-manual', x: 100, y: 100, config: {} },
          { id: 'action-1', type: 'action-delay', x: 100, y: 200, config: { delay_seconds: 1 }},
          { id: 'action-2', type: 'action-delay', x: 100, y: 300, config: { delay_seconds: 1 }}
        ],
        connections: [
          { from: 'trigger-1', to: 'action-1', fromPort: 'default', toPort: 'default' },
          { from: 'action-1', to: 'action-2', fromPort: 'default', toPort: 'default' },
          { from: 'action-2', to: 'action-1', fromPort: 'default', toPort: 'default' }  # Circular!
        ]
      })

      compiler = CompilerService.new(automation)
      result = compiler.compile!

      assert_not result[:success]
      assert result[:errors].any? { |e| e.downcase.include?('circular') }
    end

    test "warns about unreachable nodes" do
      automation = create_workflow({
        nodes: [
          { id: 'trigger-1', type: 'trigger-manual', x: 100, y: 100, config: {} },
          { id: 'success-1', type: 'output-success', x: 100, y: 200, config: {} },
          { id: 'orphan-1', type: 'action-email', x: 300, y: 200, config: { to: 'test@example.com' }}
        ],
        connections: [
          { from: 'trigger-1', to: 'success-1', fromPort: 'default', toPort: 'default' }
          # orphan-1 has no connections!
        ]
      })

      compiler = CompilerService.new(automation)
      result = compiler.compile!

      # Should still succeed but with warnings
      assert result[:success]
      assert result[:warnings].any? { |w| w.include?('orphan-1') && w.include?('not reachable') }
    end

    # ============================================
    # VARIABLE RESOLUTION
    # ============================================

    test "resolves variable references between steps" do
      automation = create_workflow({
        nodes: [
          { id: 'trigger-1', type: 'trigger-manual', x: 100, y: 100, config: {} },
          { id: 'email-1', type: 'action-email', x: 100, y: 200, config: {
            to: '{{trigger-1.context.email}}',
            subject: 'Hello {{trigger-1.context.name}}',
            body: 'Your order is ready'
          }},
          { id: 'success-1', type: 'output-success', x: 100, y: 300, config: {} }
        ],
        connections: [
          { from: 'trigger-1', to: 'email-1', fromPort: 'default', toPort: 'default' },
          { from: 'email-1', to: 'success-1', fromPort: 'default', toPort: 'default' }
        ]
      })

      compiler = CompilerService.new(automation)
      result = compiler.compile!

      assert result[:success]
      
      email_step = result[:compiled_steps].find { |s| s['node_type'] == 'action-email' }
      # Variables should be resolved to reference format
      assert_includes email_step['config']['to'], 'steps.trigger-1'
    end

    # ============================================
    # COMPLEX WORKFLOWS
    # ============================================

    test "compiles workflow with loop node" do
      automation = create_workflow({
        nodes: [
          { id: 'trigger-1', type: 'trigger-manual', x: 100, y: 100, config: {} },
          { id: 'loop-1', type: 'logic-loop', x: 100, y: 200, config: {
            items_field: 'emails',
            max_iterations: 10
          }},
          { id: 'email-1', type: 'action-email', x: 100, y: 300, config: {
            to: '{{loop-1.item}}',
            subject: 'Notification',
            body: 'Hello'
          }},
          { id: 'success-1', type: 'output-success', x: 100, y: 400, config: {} }
        ],
        connections: [
          { from: 'trigger-1', to: 'loop-1', fromPort: 'default', toPort: 'default' },
          { from: 'loop-1', to: 'email-1', fromPort: 'item', toPort: 'default' },
          { from: 'loop-1', to: 'success-1', fromPort: 'completed', toPort: 'default' }
        ]
      })

      compiler = CompilerService.new(automation)
      result = compiler.compile!

      assert result[:success]
      
      loop_step = result[:compiled_steps].find { |s| s['node_type'] == 'logic-loop' }
      assert_equal 'loop', loop_step['conditions']['type']
      assert_equal 10, loop_step['conditions']['max_iterations']
    end

    test "compiles workflow with switch node" do
      automation = create_workflow({
        nodes: [
          { id: 'trigger-1', type: 'trigger-manual', x: 100, y: 100, config: {} },
          { id: 'switch-1', type: 'logic-switch', x: 100, y: 200, config: {
            field: 'priority',
            cases: [
              { value: 'high', output_name: 'high' },
              { value: 'medium', output_name: 'medium' },
              { value: 'low', output_name: 'low' }
            ]
          }},
          { id: 'high-action', type: 'action-email', x: 0, y: 300, config: { to: 'urgent@example.com' }},
          { id: 'default-action', type: 'output-success', x: 200, y: 300, config: {} }
        ],
        connections: [
          { from: 'trigger-1', to: 'switch-1', fromPort: 'default', toPort: 'default' },
          { from: 'switch-1', to: 'high-action', fromPort: 'high', toPort: 'default' },
          { from: 'switch-1', to: 'default-action', fromPort: 'default', toPort: 'default' }
        ]
      })

      compiler = CompilerService.new(automation)
      result = compiler.compile!

      assert result[:success]
      
      switch_step = result[:compiled_steps].find { |s| s['node_type'] == 'logic-switch' }
      assert_equal 'switch', switch_step['conditions']['type']
      assert_equal 'priority', switch_step['conditions']['field']
    end

    # ============================================
    # COMPILATION STATE
    # ============================================

    test "updates automation_code with compilation results" do
      automation = create_workflow({
        nodes: [
          { id: 'trigger-1', type: 'trigger-manual', x: 100, y: 100, config: {} },
          { id: 'success-1', type: 'output-success', x: 100, y: 200, config: {} }
        ],
        connections: [
          { from: 'trigger-1', to: 'success-1', fromPort: 'default', toPort: 'default' }
        ]
      })

      assert_nil automation.compiled_at
      assert_not automation.is_compiled?

      compiler = CompilerService.new(automation)
      result = compiler.compile!

      assert result[:success]
      
      automation.reload
      assert automation.is_compiled?
      assert automation.compiled_at.present?
      assert automation.compiled_steps.is_a?(Array)
      assert_equal 2, automation.compiled_steps.size
    end

    test "validate method returns compilation result" do
      automation = create_workflow({
        nodes: [
          { id: 'trigger-1', type: 'trigger-manual', x: 100, y: 100, config: {} },
          { id: 'success-1', type: 'output-success', x: 100, y: 200, config: {} }
        ],
        connections: [
          { from: 'trigger-1', to: 'success-1', fromPort: 'default', toPort: 'default' }
        ]
      })

      compiler = CompilerService.new(automation)
      result = compiler.validate

      assert result[:success]
      assert result[:compiled_steps].is_a?(Array)
      assert_equal 2, result[:compiled_steps].size
    end

    private

    def create_workflow(definition)
      AutomationCode.create!(
        entity: @entity,
        created_by: @user,
        name: "Test Workflow #{SecureRandom.hex(4)}",
        trigger_type: 'manual',
        status: 'draft',
        code: '# Visual workflow',
        workflow_definition: definition
      )
    end
  end
end
