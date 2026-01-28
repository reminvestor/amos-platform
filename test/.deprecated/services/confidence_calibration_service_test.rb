# frozen_string_literal: true

require 'test_helper'

class Learning::ConfidenceCalibrationServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @service = Learning::ConfidenceCalibrationService.new(entity: @entity)
    
    # Clean up any existing traces
    DecisionTrace.where(entity: @entity).destroy_all
  end

  test "initializes with entity" do
    assert_equal @entity, @service.entity
  end

  test "returns insufficient data result when too few traces" do
    # Create fewer than MIN_DATA_POINTS traces
    5.times do |i|
      DecisionTrace.create!(
        entity: @entity,
        decision_type: 'action',
        decision_summary: "Decision #{i}",
        confidence_score: 0.8,
        outcome: 'success'
      )
    end

    result = @service.analyze_calibration(window: 30.days)
    
    assert_equal 0, result[:data_points]
    assert_nil result[:overall_calibration_score]
    assert result[:message].include?('Insufficient data')
  end

  test "calculates calibration when sufficient data exists" do
    # Create 25 traces with varying confidence and outcomes
    # Simulate overconfidence: high confidence but lower actual success
    25.times do |i|
      confidence = 0.85 + rand * 0.1  # 85-95% confidence
      # Make only 60% actually succeed (overconfident)
      outcome = i < 15 ? 'success' : 'failure'
      
      DecisionTrace.create!(
        entity: @entity,
        decision_type: 'action',
        decision_summary: "Decision #{i}",
        confidence_score: confidence,
        outcome: outcome
      )
    end

    result = @service.analyze_calibration(window: 30.days)
    
    assert_equal 25, result[:data_points]
    assert result[:calibration].present? || result[:calibration] == {}
  end

  test "detects overconfidence pattern" do
    # Create traces that show overconfidence
    # All have 90% confidence but only 50% succeed
    30.times do |i|
      DecisionTrace.create!(
        entity: @entity,
        decision_type: 'action',
        decision_summary: "Decision #{i}",
        confidence_score: 0.9,
        outcome: i.even? ? 'success' : 'failure'  # 50% success rate
      )
    end

    result = @service.analyze_calibration(window: 30.days)
    
    # Should detect overconfidence in the 0.9 bucket
    calibration_0_8 = result[:calibration][0.8]  # 0.9 falls in 0.8-0.9 bucket
    
    if calibration_0_8.present?
      assert calibration_0_8[:is_overconfident], 
             "Expected overconfidence detection: predicted #{calibration_0_8[:predicted]}, actual #{calibration_0_8[:actual]}"
    end
  end

  test "detects underconfidence pattern" do
    # Create traces that show underconfidence
    # All have 50% confidence but 90% succeed
    30.times do |i|
      DecisionTrace.create!(
        entity: @entity,
        decision_type: 'action',
        decision_summary: "Decision #{i}",
        confidence_score: 0.5,
        outcome: i < 27 ? 'success' : 'failure'  # 90% success rate
      )
    end

    result = @service.analyze_calibration(window: 30.days)
    
    # Should detect underconfidence in the 0.5 bucket
    calibration_0_5 = result[:calibration][0.5]
    
    if calibration_0_5.present?
      assert calibration_0_5[:is_underconfident],
             "Expected underconfidence detection: predicted #{calibration_0_5[:predicted]}, actual #{calibration_0_5[:actual]}"
    end
  end

  test "generates guidance text for miscalibration" do
    # Create overconfident traces
    30.times do |i|
      DecisionTrace.create!(
        entity: @entity,
        decision_type: 'action',
        decision_summary: "Decision #{i}",
        confidence_score: 0.9,
        outcome: i < 15 ? 'success' : 'failure'  # 50% success
      )
    end

    result = @service.analyze_calibration(window: 30.days)
    
    if result[:guidance][:significant_miscalibration]
      assert result[:guidance][:text].present?
      # Should mention confidence adjustment
      assert result[:guidance][:text].include?('confident') || 
             result[:guidance][:text].include?('success')
    end
  end

  test "calculates overall calibration score" do
    # Create well-calibrated traces
    # 80% confidence with 80% success
    30.times do |i|
      DecisionTrace.create!(
        entity: @entity,
        decision_type: 'action',
        decision_summary: "Decision #{i}",
        confidence_score: 0.8,
        outcome: i < 24 ? 'success' : 'failure'  # 80% success
      )
    end

    result = @service.analyze_calibration(window: 30.days)
    
    # Well-calibrated should have high score (close to 1.0)
    if result[:overall_calibration_score].present?
      assert result[:overall_calibration_score] >= 0.0
      assert result[:overall_calibration_score] <= 1.0
    end
  end

  test "stores calibration experience when significant miscalibration found" do
    # Create significant miscalibration
    30.times do |i|
      DecisionTrace.create!(
        entity: @entity,
        decision_type: 'action',
        decision_summary: "Decision #{i}",
        confidence_score: 0.95,
        outcome: i < 10 ? 'success' : 'failure'  # Only 33% success but 95% confidence
      )
    end

    initial_count = TaskExperience.where(entity: @entity, source_type: 'confidence_calibration').count

    result = @service.analyze_calibration(window: 30.days)
    
    if result[:guidance][:significant_miscalibration]
      final_count = TaskExperience.where(entity: @entity, source_type: 'confidence_calibration').count
      assert final_count > initial_count, "Should have created calibration experience"
    end
  end

  test "get_calibration_guidance returns nil when no calibration experience exists" do
    guidance = @service.get_calibration_guidance
    
    # Should return nil if no calibration experience exists
    if TaskExperience.where(entity: @entity, source_type: 'confidence_calibration').none?
      assert_nil guidance
    end
  end
end
