require "test_helper"

class CampaignTrackingControllerTest < ActionDispatch::IntegrationTest
  test "should get open" do
    get campaign_tracking_open_url
    assert_response :success
  end

  test "should get click" do
    get campaign_tracking_click_url
    assert_response :success
  end
end
