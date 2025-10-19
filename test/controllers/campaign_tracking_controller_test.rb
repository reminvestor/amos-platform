require "test_helper"

class CampaignTrackingControllerTest < ActionDispatch::IntegrationTest
  fixtures :campaigns, :contacts, :entities, :users

  test "should track email open" do
    campaign = campaigns(:one)
    contact = contacts(:one)

    # Create a tracking token
    token = Base64.urlsafe_encode64("#{campaign.id}:#{contact.id}")

    get email_open_path(id: token)
    assert_response :success
  end

  test "should track email click" do
    campaign = campaigns(:one)
    contact = contacts(:one)

    # Create a tracking token
    token = Base64.urlsafe_encode64("#{campaign.id}:#{contact.id}")

    get email_click_path(id: token)
    assert_response :redirect
  end
end
