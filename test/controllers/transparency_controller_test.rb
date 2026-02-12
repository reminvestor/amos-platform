# frozen_string_literal: true

require "test_helper"

class TransparencyControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Transparency routes are inside the app subdomain constraint.
    # SubdomainConfig.app_subdomains includes "" (empty) in test env,
    # so using a host with no subdomain satisfies the constraint.
    host! "example.com"

    # In CI environments, assets aren't compiled so javascript_include_tag
    # raises Propshaft::MissingAssetError for application.js.
    # Stub it since these tests verify controller behavior, not asset pipeline.
    ActionView::Base.any_instance.stubs(:javascript_include_tag).returns("")
  end

  # --- Public access ---

  test "transparency index renders successfully" do
    # Sign in because application layout requires user context for nav rendering.
    # The controller itself skips auth — this tests that the page renders.
    sign_in users(:one)
    PlatformEconomicsService.stubs(:dashboard).returns(mock_economics)
    ContributionRewardCalculator.stubs(:current_daily_emission).returns(100)
    ContributionRewardCalculator.stubs(:current_halving_multiplier).returns(1.0)
    get "/transparency"
    assert_response :success
  end

  test "transparency index handles service errors gracefully" do
    sign_in users(:one)
    PlatformEconomicsService.stubs(:dashboard).raises(StandardError.new("DB connection failed"))
    ContributionRewardCalculator.stubs(:current_daily_emission).returns(0)
    ContributionRewardCalculator.stubs(:current_halving_multiplier).returns(1.0)
    get "/transparency"
    # Should render the page with empty data, not 500
    assert_response :success
  end

  # --- API endpoint ---

  test "transparency api returns success with valid data" do
    PlatformEconomicsService.stubs(:dashboard).returns(mock_economics)
    stub_revenue_distributions

    get "/transparency/api"
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert body.key?("data")
    assert body.key?("generated_at")
  end

  test "transparency api returns error on service failure" do
    PlatformEconomicsService.stubs(:dashboard).raises(
      StandardError.new("PG::ConnectionBad: FATAL: password authentication failed")
    )

    get "/transparency/api"
    assert_response :internal_server_error

    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert body.key?("error")
  end

  test "transparency api data includes expected sections" do
    PlatformEconomicsService.stubs(:dashboard).returns(mock_economics)
    stub_revenue_distributions

    get "/transparency/api"

    body = JSON.parse(response.body)
    data = body["data"]
    assert data.key?("financials")
    assert data.key?("token_economy")
    assert data.key?("distributions")
  end

  private

  def mock_economics
    {
      financials: {
        monthly_revenue: 10_000,
        monthly_costs: 5_000,
        profit_margin: 50,
        runway_months: 24,
        profit_ratio: 0.5
      },
      token_economy: {
        total_staked: 1_000_000,
        daily_emission: 100,
        decay_rate: 0.10,
        decay_status: "healthy",
        halving_multiplier: 1.0
      },
      revenue_breakdown: { subscriptions: 8_000, services: 2_000 },
      cost_breakdown: { infrastructure: 3_000, labor: 2_000 }
    }
  end

  def stub_revenue_distributions
    if defined?(RevenueDistribution) && RevenueDistribution.respond_to?(:table_exists?)
      RevenueDistribution.stubs(:table_exists?).returns(false)
    end
  end
end
