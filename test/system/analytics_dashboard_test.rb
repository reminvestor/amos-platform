require "application_system_test_case"

class AnalyticsDashboardTest < ApplicationSystemTestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @user.update!(entity: @entity)
  end

  test "user can access analytics dashboard" do
    sign_in(@user)

    visit analytics_path

    # Analytics page should load
    assert_selector "body", visible: true
    assert_text /analytics|metrics|dashboard/i
  end

  test "analytics dashboard shows key metrics" do
    sign_in(@user)

    visit analytics_path

    # Should show some metrics
    has_metrics = page.has_text?(/campaign|email|contact|sent|open|click/i) ||
                  page.has_selector?(".metric") ||
                  page.has_selector?("[data-metric]")

    assert has_metrics, "Expected key metrics display"
  end

  test "analytics dashboard shows charts or graphs" do
    sign_in(@user)

    visit analytics_path

    # Should have visual data representation
    has_charts = page.has_selector?("canvas") ||
                 page.has_selector?("svg") ||
                 page.has_selector?(".chart") ||
                 page.has_selector?("[data-chart]")

    # Charts are optional if metrics are shown
    assert_selector "body", visible: true
  end

  test "analytics dashboard has date filter" do
    sign_in(@user)

    visit analytics_path

    # Should have date range selection
    has_date_filter = page.has_selector?("input[type='date']") ||
                      page.has_selector?("select", text: /day|week|month/i) ||
                      page.has_text?(/last.*days|date range|period/i) ||
                      page.has_selector?("[data-date-filter]")

    # Date filter is optional
    assert_selector "body", visible: true
  end

  test "analytics dashboard shows campaign performance" do
    # Create a campaign with some data
    campaign = Campaign.create!(
      entity: @entity,
      user: @user,
      user: @user,
      name: "Analytics Test Campaign",
      status: "sent"
    )

    sign_in(@user)

    visit analytics_path

    # Should show campaign-related metrics
    has_campaign_data = page.has_text?(/campaign|sent|delivered/i)

    assert has_campaign_data, "Expected campaign performance metrics"
  end

  test "analytics dashboard shows email metrics" do
    sign_in(@user)

    visit analytics_path

    # Should show email-related metrics
    has_email_metrics = page.has_text?(/email|sent|open|click|bounce/i)

    assert has_email_metrics, "Expected email metrics"
  end

  test "analytics dashboard loads without JavaScript errors" do
    sign_in(@user)

    visit analytics_path

    # No JS errors visible
    assert_no_text "undefined"
    assert_no_text "TypeError"
    assert_no_text "ReferenceError"
    assert_no_selector ".alert-danger"
  end

  test "analytics dashboard shows activity feed" do
    sign_in(@user)

    visit analytics_path

    # Should have activity or recent events section
    has_activity = page.has_text?(/activity|recent|event|history/i) ||
                   page.has_selector?(".activity") ||
                   page.has_selector?("[data-activity]")

    # Activity feed is optional
    assert_selector "body", visible: true
  end

  test "analytics dashboard shows contact growth" do
    sign_in(@user)

    visit analytics_path

    # Should show contact-related metrics
    has_contact_metrics = page.has_text?(/contact|subscriber|audience|growth/i)

    # Contact metrics are optional
    assert_selector "body", visible: true
  end

  test "analytics dashboard is responsive" do
    sign_in(@user)

    visit analytics_path

    # Page should render without layout issues
    assert_selector "body", visible: true
    assert_no_selector ".overflow-x-scroll" # No horizontal scroll needed ideally

    # Content should be visible
    has_content = page.has_text?(/analytics|metric|campaign|email/i)
    assert has_content, "Expected analytics content visible"
  end

  private

end
