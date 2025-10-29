require "test_helper"

module Scout
  class JobStatusCheckerTest < ActiveSupport::TestCase
    def setup
      @user = users(:one)
      @stream = StringIO.new
      @checker = Scout::JobStatusChecker.new(user: @user, stream: @stream)
      @checker_without_stream = Scout::JobStatusChecker.new(user: @user)

      # Use memory store for caching in tests
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new

      # Clear Rails cache before each test
      Rails.cache.clear
    end

    def teardown
      Rails.cache.clear
      Rails.cache = @original_cache if @original_cache
    end

    # check_active_job_status tests
    test "check_active_job_status returns nil when no canvas_data" do
      response_data = { message: "Test" }

      result = @checker.check_active_job_status(response_data)

      assert_nil result
    end

    test "check_active_job_status returns nil when no landing_page_id" do
      response_data = { canvas_data: { type: "other" } }

      result = @checker.check_active_job_status(response_data)

      assert_nil result
    end

    test "check_active_job_status returns nil when no job status in cache" do
      response_data = {
        canvas_data: { landing_page_id: 123 }
      }

      result = @checker.check_active_job_status(response_data)

      assert_nil result
    end

    test "check_active_job_status returns job status when found in cache" do
      landing_page_id = 123
      job_status_key = "job_status_#{@user.id}_#{landing_page_id}"

      job_status = {
        type: "image_generation",
        status: "processing",
        message: "Generating hero image..."
      }

      Rails.cache.write(job_status_key, job_status)

      response_data = {
        canvas_data: { landing_page_id: landing_page_id }
      }

      result = @checker.check_active_job_status(response_data)

      assert_not_nil result, "Should find job status in cache"
      assert_equal job_status[:type], result[:type]
      assert_equal job_status[:status], result[:status]
      assert_equal job_status[:message], result[:message]
    end

    test "check_active_job_status clears cache for completed jobs" do
      landing_page_id = 123
      job_status_key = "job_status_#{@user.id}_#{landing_page_id}"

      job_status = {
        type: "image_generation",
        status: "completed",
        message: "Image generated successfully"
      }

      Rails.cache.write(job_status_key, job_status)

      response_data = {
        canvas_data: { landing_page_id: landing_page_id }
      }

      result = @checker.check_active_job_status(response_data)

      assert_not_nil result, "Should find job status in cache"
      assert_equal "completed", result[:status]
      assert_nil Rails.cache.read(job_status_key), "Cache should be cleared for completed jobs"
    end

    test "check_active_job_status clears cache for failed jobs" do
      landing_page_id = 123
      job_status_key = "job_status_#{@user.id}_#{landing_page_id}"

      job_status = {
        type: "image_generation",
        status: "failed",
        message: "Image generation failed"
      }

      Rails.cache.write(job_status_key, job_status)

      response_data = {
        canvas_data: { landing_page_id: landing_page_id }
      }

      result = @checker.check_active_job_status(response_data)

      assert_not_nil result, "Should find job status in cache"
      assert_equal "failed", result[:status]
      assert_nil Rails.cache.read(job_status_key), "Cache should be cleared for failed jobs"
    end

    test "check_active_job_status keeps cache for processing jobs" do
      landing_page_id = 123
      job_status_key = "job_status_#{@user.id}_#{landing_page_id}"

      job_status = {
        type: "image_generation",
        status: "processing",
        message: "Still processing..."
      }

      Rails.cache.write(job_status_key, job_status)

      response_data = {
        canvas_data: { landing_page_id: landing_page_id }
      }

      result = @checker.check_active_job_status(response_data)

      assert_equal "processing", result[:status]
      assert_not_nil Rails.cache.read(job_status_key), "Cache should be kept for processing jobs"
    end

    test "check_active_job_status handles integer landing_page_id" do
      landing_page_id = 456
      job_status_key = "job_status_#{@user.id}_#{landing_page_id}"

      job_status = { type: "test", status: "completed" }
      Rails.cache.write(job_status_key, job_status)

      response_data = {
        canvas_data: { landing_page_id: landing_page_id }
      }

      result = @checker.check_active_job_status(response_data)

      assert_not_nil result, "Should find job with correct cache key format"
      assert_equal job_status[:type], result[:type]
    end

    # send_job_started_status_if_exists tests
    test "send_job_started_status_if_exists does nothing without stream" do
      response_data = {
        canvas_data: { landing_page_id: 123 }
      }

      # Should not raise
      assert_nothing_raised do
        @checker_without_stream.send_job_started_status_if_exists(response_data)
      end
    end

    test "send_job_started_status_if_exists does nothing without canvas_data" do
      response_data = { message: "Test" }

      @checker.send_job_started_status_if_exists(response_data)

      # Stream should be empty
      assert_equal "", @stream.string
    end

    test "send_job_started_status_if_exists does nothing without landing_page_id" do
      response_data = { canvas_data: { type: "other" } }

      @checker.send_job_started_status_if_exists(response_data)

      assert_equal "", @stream.string
    end

    test "send_job_started_status_if_exists does nothing when no job status" do
      response_data = {
        canvas_data: { landing_page_id: 123 }
      }

      @checker.send_job_started_status_if_exists(response_data)

      assert_equal "", @stream.string
    end

    test "send_job_started_status_if_exists sends SSE when job is processing" do
      landing_page_id = 123
      job_status_key = "job_status_#{@user.id}_#{landing_page_id}"

      job_status = {
        type: "image_generation",
        status: "processing",
        message: "Generating images..."
      }

      Rails.cache.write(job_status_key, job_status)

      response_data = {
        canvas_data: { landing_page_id: landing_page_id }
      }

      @checker.send_job_started_status_if_exists(response_data)

      stream_content = @stream.string
      assert stream_content.present?
      assert stream_content.start_with?("data: ")
      assert stream_content.end_with?("\n\n")

      # Parse JSON
      json_str = stream_content.gsub("data: ", "").gsub("\n\n", "")
      data = JSON.parse(json_str)

      assert_equal "job_status", data["type"]
      assert_equal "image_generation", data["data"]["type"]
      assert_equal "processing", data["data"]["status"]
      assert_equal "Generating images...", data["data"]["message"]
    end

    test "send_job_started_status_if_exists does not send when job is completed" do
      landing_page_id = 123
      job_status_key = "job_status_#{@user.id}_#{landing_page_id}"

      job_status = {
        type: "image_generation",
        status: "completed",
        message: "Done"
      }

      Rails.cache.write(job_status_key, job_status)

      response_data = {
        canvas_data: { landing_page_id: landing_page_id }
      }

      @checker.send_job_started_status_if_exists(response_data)

      assert_equal "", @stream.string, "Should not send SSE for completed jobs"
    end

    test "send_job_started_status_if_exists does not send when job is failed" do
      landing_page_id = 123
      job_status_key = "job_status_#{@user.id}_#{landing_page_id}"

      job_status = {
        type: "image_generation",
        status: "failed",
        message: "Failed"
      }

      Rails.cache.write(job_status_key, job_status)

      response_data = {
        canvas_data: { landing_page_id: landing_page_id }
      }

      @checker.send_job_started_status_if_exists(response_data)

      assert_equal "", @stream.string, "Should not send SSE for failed jobs"
    end

    test "send_job_started_status_if_exists produces valid SSE format" do
      landing_page_id = 123
      job_status_key = "job_status_#{@user.id}_#{landing_page_id}"

      job_status = {
        type: "test",
        status: "processing"
      }

      Rails.cache.write(job_status_key, job_status)

      response_data = {
        canvas_data: { landing_page_id: landing_page_id }
      }

      @checker.send_job_started_status_if_exists(response_data)

      stream_content = @stream.string

      # Valid SSE format: "data: {...}\n\n"
      assert stream_content.present?, "Stream should have content"
      assert stream_content.start_with?("data: "), "Stream should start with 'data: '"
      assert stream_content.end_with?("\n\n"), "Stream should end with \\n\\n"

      # Should be valid JSON
      json_str = stream_content.gsub("data: ", "").gsub("\n\n", "")
      assert_nothing_raised do
        JSON.parse(json_str)
      end
    end

    # Cache key format tests
    test "uses correct cache key format" do
      landing_page_id = 789
      expected_key = "job_status_#{@user.id}_#{landing_page_id}"

      job_status = { type: "test", status: "processing" }
      Rails.cache.write(expected_key, job_status)

      response_data = {
        canvas_data: { landing_page_id: landing_page_id }
      }

      result = @checker.check_active_job_status(response_data)

      assert_not_nil result, "Should find job with correct cache key format"
      assert_equal "test", result[:type]
    end

    test "different users have different cache keys" do
      other_user = users(:two)
      other_checker = Scout::JobStatusChecker.new(user: other_user)

      landing_page_id = 123
      job_status_user1 = { type: "user1_job", status: "processing" }
      job_status_user2 = { type: "user2_job", status: "processing" }

      Rails.cache.write("job_status_#{@user.id}_#{landing_page_id}", job_status_user1)
      Rails.cache.write("job_status_#{other_user.id}_#{landing_page_id}", job_status_user2)

      response_data = {
        canvas_data: { landing_page_id: landing_page_id }
      }

      result1 = @checker.check_active_job_status(response_data)
      result2 = other_checker.check_active_job_status(response_data)

      assert_equal "user1_job", result1[:type]
      assert_equal "user2_job", result2[:type]
    end

    # Edge cases
    test "handles stream without flush method" do
      stream_without_flush = Object.new
      def stream_without_flush.write(data)
        @data = data
      end

      checker = Scout::JobStatusChecker.new(user: @user, stream: stream_without_flush)

      landing_page_id = 123
      job_status_key = "job_status_#{@user.id}_#{landing_page_id}"

      Rails.cache.write(job_status_key, { type: "test", status: "processing" })

      response_data = {
        canvas_data: { landing_page_id: landing_page_id }
      }

      # Should not raise even though stream doesn't have flush method
      assert_nothing_raised do
        checker.send_job_started_status_if_exists(response_data)
      end
    end
  end
end
