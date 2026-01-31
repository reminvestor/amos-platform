# frozen_string_literal: true

require 'test_helper'

class AmosWorkReviewerTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @bounty = create_test_bounty
  end

  # === FALLBACK REVIEW ===

  test "returns fallback approval on LLM failure" do
    AmosWorkReviewer.stub(:call_llm, ->(_) { raise "LLM unavailable" }) do
      result = AmosWorkReviewer.review(
        bounty: @bounty,
        submission_notes: 'Fixed the bug'
      )

      assert result[:approved]
      assert_equal @bounty.points, result[:final_points]
      assert result[:feedback].include?('Thank you')
    end
  end

  # === REVIEW LOGIC ===

  test "approves with point adjustment" do
    mock_response = {
      'approved' => true,
      'final_points' => 275,
      'point_adjustment_percent' => 10,
      'quality_score' => 8,
      'feedback' => 'Great implementation!',
      'issues' => [],
      'praise' => ['Clean code', 'Good tests']
    }.to_json

    AmosWorkReviewer.stub(:call_llm, ->(_) { mock_response }) do
      result = AmosWorkReviewer.review(
        bounty: @bounty,
        submission_notes: 'Implemented feature with tests'
      )

      assert result[:approved]
      assert_equal 275, result[:final_points]
      assert_equal 10, result[:point_adjustment_percent]
      assert_equal 8, result[:quality_score]
      assert_equal ['Clean code', 'Good tests'], result[:praise]
    end
  end

  test "rejects with issues" do
    mock_response = {
      'approved' => false,
      'final_points' => 200,
      'point_adjustment_percent' => -20,
      'quality_score' => 4,
      'feedback' => 'Needs work',
      'issues' => ['Missing tests', 'No documentation'],
      'praise' => []
    }.to_json

    AmosWorkReviewer.stub(:call_llm, ->(_) { mock_response }) do
      result = AmosWorkReviewer.review(
        bounty: @bounty,
        submission_notes: 'Quick fix'
      )

      assert_not result[:approved]
      assert_equal 200, result[:final_points]
      assert_equal ['Missing tests', 'No documentation'], result[:issues]
    end
  end

  test "clamps final points to max 1.5x original" do
    mock_response = {
      'approved' => true,
      'final_points' => 1000,  # Way above 250 * 1.5 = 375
      'point_adjustment_percent' => 100,
      'quality_score' => 10,
      'feedback' => 'Amazing!',
      'issues' => [],
      'praise' => []
    }.to_json

    AmosWorkReviewer.stub(:call_llm, ->(_) { mock_response }) do
      result = AmosWorkReviewer.review(
        bounty: @bounty,
        submission_notes: 'Exceptional work'
      )

      assert_equal 375, result[:final_points]  # Clamped to 1.5x
    end
  end

  test "clamps adjustment percent to valid range" do
    mock_response = {
      'approved' => true,
      'final_points' => 250,
      'point_adjustment_percent' => 100,  # Over limit
      'quality_score' => 5,
      'feedback' => 'OK',
      'issues' => [],
      'praise' => []
    }.to_json

    AmosWorkReviewer.stub(:call_llm, ->(_) { mock_response }) do
      result = AmosWorkReviewer.review(
        bounty: @bounty,
        submission_notes: 'Work done'
      )

      assert_equal 50, result[:point_adjustment_percent]  # Clamped to 50
    end
  end

  # === AUTO REVIEW ===

  test "auto_review_simple approves with sufficient notes" do
    result = AmosWorkReviewer.auto_review_simple(
      bounty: @bounty,
      submission_notes: 'Fixed the typo in the documentation file README.md by changing foo to bar.'
    )

    assert result[:approved]
    assert_equal @bounty.points, result[:final_points]
    assert_equal 7, result[:quality_score]
  end

  test "auto_review_simple rejects with insufficient notes" do
    result = AmosWorkReviewer.auto_review_simple(
      bounty: @bounty,
      submission_notes: 'done'
    )

    assert_not result[:approved]
    assert result[:issues].include?('Submission notes too brief')
  end

  test "auto_review_simple rejects empty notes" do
    result = AmosWorkReviewer.auto_review_simple(
      bounty: @bounty,
      submission_notes: ''
    )

    assert_not result[:approved]
  end

  # === CODE DIFF HANDLING ===

  test "includes code diff in review prompt" do
    prompt_received = nil

    AmosWorkReviewer.stub(:call_llm, ->(prompt) {
      prompt_received = prompt
      { 'approved' => true, 'final_points' => 250 }.to_json
    }) do
      AmosWorkReviewer.review(
        bounty: @bounty,
        submission_notes: 'Fixed bug',
        code_diff: "+def fixed_method\n+  return true\n+end"
      )
    end

    assert prompt_received.include?('CODE CHANGES')
    assert prompt_received.include?('fixed_method')
  end

  test "includes artifacts in review prompt" do
    prompt_received = nil

    AmosWorkReviewer.stub(:call_llm, ->(prompt) {
      prompt_received = prompt
      { 'approved' => true, 'final_points' => 250 }.to_json
    }) do
      AmosWorkReviewer.review(
        bounty: @bounty,
        submission_notes: 'Created tutorial',
        artifacts: ['https://blog.example.com/tutorial', 'https://youtube.com/watch?v=123']
      )
    end

    assert prompt_received.include?('ARTIFACTS')
    assert prompt_received.include?('blog.example.com')
  end

  # === JSON PARSING ===

  test "handles JSON wrapped in markdown" do
    markdown_response = "```json\n{\"approved\": true, \"final_points\": 300}\n```"

    AmosWorkReviewer.stub(:call_llm, ->(_) { markdown_response }) do
      result = AmosWorkReviewer.review(
        bounty: @bounty,
        submission_notes: 'Work done'
      )

      assert result[:approved]
      assert_equal 300, result[:final_points]
    end
  end

  test "handles invalid JSON with fallback" do
    AmosWorkReviewer.stub(:call_llm, ->(_) { "Invalid response" }) do
      result = AmosWorkReviewer.review(
        bounty: @bounty,
        submission_notes: 'Work done'
      )

      # Should return fallback approval
      assert result[:approved]
      assert_equal @bounty.points, result[:final_points]
    end
  end

  private

  def create_test_bounty
    Bounty.create!(
      entity: @entity,
      title: 'Test bounty',
      description: 'Test description',
      bounty_type: 'feature',
      points: 250
    )
  end
end
