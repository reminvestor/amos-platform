require "test_helper"

class CrawlerJobsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get crawler_jobs_index_url
    assert_response :success
  end

  test "should get new" do
    get crawler_jobs_new_url
    assert_response :success
  end

  test "should get create" do
    get crawler_jobs_create_url
    assert_response :success
  end
end
