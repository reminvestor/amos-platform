require "test_helper"

class SocialMediaAccountsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get social_media_accounts_index_url
    assert_response :success
  end

  test "should get new" do
    get social_media_accounts_new_url
    assert_response :success
  end

  test "should get create" do
    get social_media_accounts_create_url
    assert_response :success
  end

  test "should get callback" do
    get social_media_accounts_callback_url
    assert_response :success
  end

  test "should get disconnect" do
    get social_media_accounts_disconnect_url
    assert_response :success
  end
end
