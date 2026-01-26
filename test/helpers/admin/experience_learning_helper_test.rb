# frozen_string_literal: true

require "test_helper"

class Admin::ExperienceLearningHelperTest < ActionView::TestCase
  include Admin::ExperienceLearningHelper

  # === Source Type Badge Tests ===

  test "source_type_badge_class returns bg-primary for semantic_advantage" do
    assert_equal "bg-primary", source_type_badge_class("semantic_advantage")
  end

  test "source_type_badge_class returns bg-danger for immediate_failure" do
    assert_equal "bg-danger", source_type_badge_class("immediate_failure")
  end

  test "source_type_badge_class returns bg-info for reflection" do
    assert_equal "bg-info", source_type_badge_class("reflection")
  end

  test "source_type_badge_class returns bg-secondary for manual" do
    assert_equal "bg-secondary", source_type_badge_class("manual")
  end

  test "source_type_badge_class returns bg-success for promoted_from_entity" do
    assert_equal "bg-success", source_type_badge_class("promoted_from_entity")
  end

  test "source_type_badge_class returns bg-warning for confidence_calibration" do
    assert_equal "bg-warning text-dark", source_type_badge_class("confidence_calibration")
  end

  test "source_type_badge_class returns bg-secondary for unknown source" do
    assert_equal "bg-secondary", source_type_badge_class("unknown_source")
  end

  test "source_type_badge_class returns bg-secondary for nil" do
    assert_equal "bg-secondary", source_type_badge_class(nil)
  end

  # === Utility Badge Tests ===

  test "utility_badge_class returns bg-success for high utility (>=0.8)" do
    assert_equal "bg-success", utility_badge_class(0.9)
    assert_equal "bg-success", utility_badge_class(0.8)
    assert_equal "bg-success", utility_badge_class(1.0)
  end

  test "utility_badge_class returns bg-info for good utility (0.6-0.79)" do
    assert_equal "bg-info", utility_badge_class(0.7)
    assert_equal "bg-info", utility_badge_class(0.6)
    assert_equal "bg-info", utility_badge_class(0.79)
  end

  test "utility_badge_class returns bg-warning for medium utility (0.4-0.59)" do
    assert_equal "bg-warning text-dark", utility_badge_class(0.5)
    assert_equal "bg-warning text-dark", utility_badge_class(0.4)
    assert_equal "bg-warning text-dark", utility_badge_class(0.59)
  end

  test "utility_badge_class returns bg-danger for low utility (<0.4)" do
    assert_equal "bg-danger", utility_badge_class(0.3)
    assert_equal "bg-danger", utility_badge_class(0.0)
    assert_equal "bg-danger", utility_badge_class(0.39)
  end

  test "utility_badge_class returns bg-secondary for nil" do
    assert_equal "bg-secondary", utility_badge_class(nil)
  end

  # === Calibration Badge Tests ===

  test "calibration_badge_class returns bg-success for well-calibrated (>=0.85)" do
    assert_equal "bg-success", calibration_badge_class(0.9)
    assert_equal "bg-success", calibration_badge_class(0.85)
    assert_equal "bg-success", calibration_badge_class(1.0)
  end

  test "calibration_badge_class returns bg-info for good calibration (0.7-0.84)" do
    assert_equal "bg-info", calibration_badge_class(0.8)
    assert_equal "bg-info", calibration_badge_class(0.7)
    assert_equal "bg-info", calibration_badge_class(0.84)
  end

  test "calibration_badge_class returns bg-warning for fair calibration (0.5-0.69)" do
    assert_equal "bg-warning text-dark", calibration_badge_class(0.6)
    assert_equal "bg-warning text-dark", calibration_badge_class(0.5)
    assert_equal "bg-warning text-dark", calibration_badge_class(0.69)
  end

  test "calibration_badge_class returns bg-danger for poor calibration (<0.5)" do
    assert_equal "bg-danger", calibration_badge_class(0.4)
    assert_equal "bg-danger", calibration_badge_class(0.0)
    assert_equal "bg-danger", calibration_badge_class(0.49)
  end

  test "calibration_badge_class returns bg-secondary for nil" do
    assert_equal "bg-secondary", calibration_badge_class(nil)
  end

  # === Success Rate Badge Tests ===

  test "success_rate_badge_class returns bg-success for high rate (>=0.75)" do
    assert_equal "bg-success", success_rate_badge_class(0.8)
    assert_equal "bg-success", success_rate_badge_class(0.75)
    assert_equal "bg-success", success_rate_badge_class(1.0)
  end

  test "success_rate_badge_class returns bg-warning for medium rate (0.5-0.74)" do
    assert_equal "bg-warning text-dark", success_rate_badge_class(0.6)
    assert_equal "bg-warning text-dark", success_rate_badge_class(0.5)
    assert_equal "bg-warning text-dark", success_rate_badge_class(0.74)
  end

  test "success_rate_badge_class returns bg-danger for low rate (<0.5)" do
    assert_equal "bg-danger", success_rate_badge_class(0.4)
    assert_equal "bg-danger", success_rate_badge_class(0.0)
    assert_equal "bg-danger", success_rate_badge_class(0.49)
  end

  test "success_rate_badge_class returns bg-secondary for nil" do
    assert_equal "bg-secondary", success_rate_badge_class(nil)
  end

  # === Conflict Type Badge Tests ===

  test "conflict_type_badge returns danger badge for success_rate_divergence" do
    result = conflict_type_badge("success_rate_divergence")
    assert_includes result, "bg-danger"
    assert_includes result, "Success Rate Divergence"
  end

  test "conflict_type_badge returns warning badge for semantic_opposition" do
    result = conflict_type_badge("semantic_opposition")
    assert_includes result, "bg-warning"
    assert_includes result, "Semantic Opposition"
  end

  test "conflict_type_badge returns secondary badge for unknown type" do
    result = conflict_type_badge("unknown_type")
    assert_includes result, "bg-secondary"
    assert_includes result, "unknown_type"
  end

  # === Detection Method Badge Tests ===

  test "detection_method_badge returns primary badge for keyword_match" do
    result = detection_method_badge("keyword_match")
    assert_includes result, "bg-primary"
    assert_includes result, "Keyword"
  end

  test "detection_method_badge returns danger badge for retry_detected" do
    result = detection_method_badge("retry_detected")
    assert_includes result, "bg-danger"
    assert_includes result, "Retry"
  end

  test "detection_method_badge returns success badge for topic_change" do
    result = detection_method_badge("topic_change")
    assert_includes result, "bg-success"
    assert_includes result, "Topic Change"
  end

  test "detection_method_badge returns secondary badge for unknown method" do
    result = detection_method_badge("unknown_method")
    assert_includes result, "bg-secondary"
    assert_includes result, "unknown_method"
  end
end
