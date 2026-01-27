require 'test_helper'

class GetEmailSequenceDataToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:default)
    @user = users(:default)
    @tool = Tools::GetDataTool.new(
      entity: @entity,
      user: @user,
      session: nil,
      execution: nil
    )
  end

  test "queries email sequences" do
    result = @tool.execute({
      'object_type' => 'email_sequences',
      'options' => {
        'limit' => 10
      }
    })

    assert result[:success]
    assert_equal 'email_sequences', result[:object_type]
    assert result[:records].is_a?(Array)
  end

  test "filters email sequences by status" do
    result = @tool.execute({
      'object_type' => 'email_sequences',
      'filters' => {
        'status' => 'draft'
      }
    })

    assert result[:success]
    assert result[:records].all? { |r| r['status'] == 'draft' }
  end

  test "queries sequence steps" do
    sequence = email_sequences(:welcome_sequence)

    result = @tool.execute({
      'object_type' => 'sequence_steps',
      'filters' => {
        'email_sequence_id' => sequence.id
      }
    })

    assert result[:success]
    assert_equal 'sequence_steps', result[:object_type]
  end

  test "queries sequence enrollments" do
    result = @tool.execute({
      'object_type' => 'sequence_enrollments',
      'filters' => {
        'status' => 'active'
      }
    })

    assert result[:success]
    assert_equal 'sequence_enrollments', result[:object_type]
  end
end
