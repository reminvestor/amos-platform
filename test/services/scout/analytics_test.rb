require "test_helper"

module Scout
  class AnalyticsTest < ActiveSupport::TestCase
    def setup
      @entity = entities(:one)
      @user = users(:one)
      @analytics = Scout::Analytics.new(entity: @entity, user: @user)
    end

    # calculate_avg_open_rate tests
    test "calculate_avg_open_rate returns 0 when no campaigns exist" do
      # Clear all campaigns
      @entity.campaigns.destroy_all

      assert_equal 0, @analytics.calculate_avg_open_rate
    end

    test "calculate_avg_open_rate returns 0 when no campaigns have stats" do
      # Create campaigns without mailgun_stats
      3.times do
        @entity.campaigns.create!(
          user: @user,
          name: "Test Campaign",
          description: "Test description",
          status: "draft",
          mailgun_stats: nil
        )
      end

      assert_equal 0, @analytics.calculate_avg_open_rate
    end

    test "calculate_avg_open_rate calculates correct average" do
      # Clear existing campaigns
      @entity.campaigns.destroy_all

      # Campaign 1: 100 sent, 20 opened (20% rate)
      @entity.campaigns.create!(
        user: @user,
        name: "Campaign 1",
        description: "Test 1",
        status: "completed",
        mailgun_stats: { "sent" => 100, "opened" => 20 }
      )

      # Campaign 2: 200 sent, 80 opened (40% rate)
      @entity.campaigns.create!(
        user: @user,
        name: "Campaign 2",
        description: "Test 2",
        status: "completed",
        mailgun_stats: { "sent" => 200, "opened" => 80 }
      )

      # Total: 300 sent, 100 opened = 33.3%
      assert_equal 33.3, @analytics.calculate_avg_open_rate
    end

    test "calculate_avg_open_rate handles missing sent/opened fields" do
      @entity.campaigns.destroy_all

      # Campaign with empty stats
      @entity.campaigns.create!(
        user: @user,
        name: "Campaign",
        description: "Test",
        status: "completed",
        mailgun_stats: {}
      )

      assert_equal 0, @analytics.calculate_avg_open_rate
    end

    test "calculate_avg_open_rate ignores campaigns with nil stats" do
      @entity.campaigns.destroy_all

      # Campaign with stats
      @entity.campaigns.create!(
        user: @user,
        name: "Campaign 1",
        description: "Test",
        status: "completed",
        mailgun_stats: { "sent" => 100, "opened" => 25 }
      )

      # Campaign without stats (should be ignored)
      @entity.campaigns.create!(
        user: @user,
        name: "Campaign 2",
        description: "Test",
        status: "draft",
        mailgun_stats: nil
      )

      # Should only use Campaign 1: 25/100 = 25%
      assert_equal 25.0, @analytics.calculate_avg_open_rate
    end

    test "calculate_avg_open_rate rounds to 1 decimal place" do
      @entity.campaigns.destroy_all

      @entity.campaigns.create!(
        user: @user,
        name: "Campaign",
        description: "Test",
        status: "completed",
        mailgun_stats: { "sent" => 3, "opened" => 1 }
      )

      # 1/3 = 33.333...% should round to 33.3
      assert_equal 33.3, @analytics.calculate_avg_open_rate
    end

    # load_form_submissions_data tests
    test "load_form_submissions_data returns empty when no submissions" do
      # Ensure no submissions exist
      LandingPageSubmission.delete_all

      result = @analytics.load_form_submissions_data

      assert_equal 0, result[:submissions].length
      assert_equal 0, result[:stats][:total]
      assert_nil result[:landing_page]
    end

    test "load_form_submissions_data filters by landing_page_id" do
      # Create landing pages
      lp1 = LandingPage.create!(
        user: @user,
        entity: @entity,
        title: "LP 1",
        slug: "lp-1",
        metadata: {}
      )

      lp2 = LandingPage.create!(
        user: @user,
        entity: @entity,
        title: "LP 2",
        slug: "lp-2",
        metadata: {}
      )

      # Create submissions
      LandingPageSubmission.create!(
        landing_page: lp1,
        form_type: "contact",
        status: "processed",
        submission_data: { email: "test1@example.com" }
      )

      LandingPageSubmission.create!(
        landing_page: lp2,
        form_type: "contact",
        status: "processed",
        submission_data: { email: "test2@example.com" }
      )

      result = @analytics.load_form_submissions_data(landing_page_id: lp1.id)

      assert_equal 1, result[:submissions].length
      assert_equal lp1.id, result[:submissions][0][:landing_page][:id]
      assert_equal lp1, result[:landing_page]
    end

    test "load_form_submissions_data filters by form_type" do
      lp = LandingPage.create!(
        user: @user,
        entity: @entity,
        title: "LP",
        slug: "lp",
        metadata: {}
      )

      LandingPageSubmission.create!(
        landing_page: lp,
        form_type: "contact",
        status: "processed",
        submission_data: { email: "test@example.com" }
      )

      LandingPageSubmission.create!(
        landing_page: lp,
        form_type: "newsletter",
        status: "processed",
        submission_data: { email: "test@example.com" }
      )

      result = @analytics.load_form_submissions_data(form_type: "contact")

      assert_equal 1, result[:submissions].length
      assert_equal "contact", result[:submissions][0][:form_type]
    end

    test "load_form_submissions_data filters by status" do
      lp = LandingPage.create!(
        user: @user,
        entity: @entity,
        title: "LP",
        slug: "lp",
        metadata: {}
      )

      LandingPageSubmission.create!(
        landing_page: lp,
        form_type: "contact",
        status: "pending",
        submission_data: { email: "test@example.com" }
      )

      LandingPageSubmission.create!(
        landing_page: lp,
        form_type: "contact",
        status: "processed",
        submission_data: { email: "test@example.com" }
      )

      result = @analytics.load_form_submissions_data(status: "pending")

      assert_equal 1, result[:submissions].length
      assert_equal "pending", result[:submissions][0][:status]
    end

    test "load_form_submissions_data includes formatted submission data" do
      lp = LandingPage.create!(
        user: @user,
        entity: @entity,
        title: "Test LP",
        slug: "test-lp",
        metadata: {}
      )

      submission = LandingPageSubmission.create!(
        landing_page: lp,
        form_type: "contact",
        status: "processed",
        submission_data: { email: "test@example.com", name: "John" },
        source_ip: "127.0.0.1",
        referrer: "https://google.com"
      )

      result = @analytics.load_form_submissions_data

      formatted = result[:submissions].first
      assert_equal submission.id, formatted[:id]
      assert_equal "contact", formatted[:form_type]
      assert_equal "processed", formatted[:status]
      assert formatted[:submitted_at].present?
      assert_equal "127.0.0.1", formatted[:source_ip]
      assert_equal "https://google.com", formatted[:referrer]
      assert_equal lp.id, formatted[:landing_page][:id]
      assert_equal "Test LP", formatted[:landing_page][:title]
      assert formatted[:submission_data].present?
    end

    test "load_form_submissions_data includes stats" do
      lp = LandingPage.create!(
        user: @user,
        entity: @entity,
        title: "LP",
        slug: "lp",
        metadata: {}
      )

      # Create submissions with different statuses
      LandingPageSubmission.create!(landing_page: lp, form_type: "contact", status: "processed", submission_data: { email: "test@example.com" })
      LandingPageSubmission.create!(landing_page: lp, form_type: "contact", status: "processed", submission_data: { email: "test@example.com" })
      LandingPageSubmission.create!(landing_page: lp, form_type: "contact", status: "pending", submission_data: { email: "test@example.com" })
      LandingPageSubmission.create!(landing_page: lp, form_type: "contact", status: "spam", submission_data: { email: "test@example.com" })

      result = @analytics.load_form_submissions_data

      assert_equal 4, result[:stats][:total]
      assert_equal 2, result[:stats][:processed]
      assert_equal 1, result[:stats][:pending]
      assert_equal 1, result[:stats][:spam]
      assert_equal 50.0, result[:stats][:conversion_rate] # 2/4 = 50%
    end

    test "load_form_submissions_data limits to 50 submissions" do
      lp = LandingPage.create!(
        user: @user,
        entity: @entity,
        title: "LP",
        slug: "lp",
        metadata: {}
      )

      # Create 60 submissions
      60.times do |i|
        LandingPageSubmission.create!(
          landing_page: lp,
          form_type: "contact",
          status: "processed",
          submission_data: { email: "test#{i}@example.com" }
        )
      end

      result = @analytics.load_form_submissions_data

      assert_equal 50, result[:submissions].length
      assert_equal 60, result[:stats][:total]
      assert result[:pagination][:has_next]
    end

    # calculate_submission_stats tests
    test "calculate_submission_stats returns correct counts" do
      lp = LandingPage.create!(
        user: @user,
        entity: @entity,
        title: "LP",
        slug: "lp",
        metadata: {}
      )

      base_query = LandingPageSubmission.where(landing_page: lp)

      LandingPageSubmission.create!(landing_page: lp, form_type: "contact", status: "processed", submission_data: { email: "test@example.com" })
      LandingPageSubmission.create!(landing_page: lp, form_type: "contact", status: "duplicate", submission_data: { email: "test@example.com" })
      LandingPageSubmission.create!(landing_page: lp, form_type: "contact", status: "pending", submission_data: { email: "test@example.com" })
      LandingPageSubmission.create!(landing_page: lp, form_type: "contact", status: "failed", submission_data: { email: "test@example.com" })
      LandingPageSubmission.create!(landing_page: lp, form_type: "contact", status: "spam", submission_data: { email: "test@example.com" })

      stats = @analytics.calculate_submission_stats(base_query)

      assert_equal 5, stats[:total]
      assert_equal 2, stats[:processed] # processed + duplicate
      assert_equal 1, stats[:pending]
      assert_equal 1, stats[:failed]
      assert_equal 1, stats[:spam]
      assert_equal 40.0, stats[:conversion_rate] # 2/5 = 40%
    end

    test "calculate_submission_stats returns 0 conversion rate when no submissions" do
      lp = LandingPage.create!(
        user: @user,
        entity: @entity,
        title: "LP",
        slug: "lp",
        metadata: {}
      )

      base_query = LandingPageSubmission.where(landing_page: lp)

      stats = @analytics.calculate_submission_stats(base_query)

      assert_equal 0, stats[:total]
      assert_equal 0.0, stats[:conversion_rate]
    end

    # load_workflow_analytics_data tests
    test "load_workflow_analytics_data returns analytics from ObservabilityService" do
      # Mock ObservabilityService
      mock_observability = mock('observability')
      mock_observability.expects(:workflow_analytics).with(30.days).returns({ total: 10 })
      mock_observability.expects(:tool_analytics).with(30.days).returns({ total_calls: 50 })
      mock_observability.expects(:user_analytics).with(30.days).returns({ active_users: 5 })
      mock_observability.expects(:ai_metrics).with(30.days).returns({ tokens: 1000 })
      mock_observability.expects(:performance_metrics).with(30.days).returns({ avg_response: 200 })

      ObservabilityService.stubs(:instance).returns(mock_observability)

      result = @analytics.load_workflow_analytics_data

      assert_equal({ total: 10 }, result[:workflow_analytics])
      assert_equal({ total_calls: 50 }, result[:tool_analytics])
      assert_equal({ active_users: 5 }, result[:user_analytics])
      assert_equal({ tokens: 1000 }, result[:ai_metrics])
      assert_equal({ avg_response: 200 }, result[:performance_metrics])
      assert_equal 30, result[:period_days]
      assert result[:generated_at].present?
    end

    test "load_workflow_analytics_data accepts custom period" do
      mock_observability = mock('observability')
      mock_observability.expects(:workflow_analytics).with(7.days).returns({})
      mock_observability.expects(:tool_analytics).with(7.days).returns({})
      mock_observability.expects(:user_analytics).with(7.days).returns({})
      mock_observability.expects(:ai_metrics).with(7.days).returns({})
      mock_observability.expects(:performance_metrics).with(7.days).returns({})

      ObservabilityService.stubs(:instance).returns(mock_observability)

      result = @analytics.load_workflow_analytics_data(period: 7)

      assert_equal 7, result[:period_days]
    end

    test "load_workflow_analytics_data includes timestamp" do
      mock_observability = mock('observability')
      mock_observability.stubs(:workflow_analytics).returns({})
      mock_observability.stubs(:tool_analytics).returns({})
      mock_observability.stubs(:user_analytics).returns({})
      mock_observability.stubs(:ai_metrics).returns({})
      mock_observability.stubs(:performance_metrics).returns({})

      ObservabilityService.stubs(:instance).returns(mock_observability)

      before_time = Time.current
      result = @analytics.load_workflow_analytics_data
      after_time = Time.current

      assert result[:generated_at] >= before_time
      assert result[:generated_at] <= after_time
    end
  end
end
