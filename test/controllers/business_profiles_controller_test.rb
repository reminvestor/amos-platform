require "test_helper"

class BusinessProfilesControllerTest < ActionDispatch::IntegrationTest
  test "should get edit" do
    get business_profiles_edit_url
    assert_response :success
  end

  test "should get update" do
    get business_profiles_update_url
    assert_response :success
  end
end
