# frozen_string_literal: true

# CaptureWebPageJob
# Background job that captures a screenshot and extracts text from a web page.
# Streams the result back to the Scout chat interface via ActionCable or SSE.
#
# Usage:
#   CaptureWebPageJob.perform_later(
#     url: "https://example.com",
#     entity_id: 123,
#     user_id: 456,
#     task_session_id: 789
#   )
#
class CaptureWebPageJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff for transient failures
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Don't retry for these specific errors
  discard_on ArgumentError

  def perform(url:, entity_id:, user_id:, task_session_id: nil, canvas_request_id: nil)
    @url = url
    @entity_id = entity_id
    @user_id = user_id
    @task_session_id = task_session_id
    @canvas_request_id = canvas_request_id || SecureRandom.uuid

    Rails.logger.info "[CaptureWebPageJob] Starting capture for #{url} (entity: #{entity_id}, user: #{user_id})"

    # Check cache first
    cached_result = check_cache
    if cached_result
      Rails.logger.info "[CaptureWebPageJob] Using cached capture for #{url}"
      broadcast_result(cached_result)
      return
    end

    # Perform the capture
    service = WebPageCaptureService.new(url: url, entity_id: entity_id)
    result = service.capture

    if result[:success]
      # Cache the successful result
      cache_result(result)

      # Store in database for reference
      store_capture_record(result)
    end

    # Broadcast result to the user's canvas
    broadcast_result(result)

    Rails.logger.info "[CaptureWebPageJob] Capture complete for #{url}: #{result[:success] ? 'success' : 'failed'}"
  rescue StandardError => e
    Rails.logger.error "[CaptureWebPageJob] Error capturing #{url}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")

    # Broadcast error to user
    broadcast_result({
      success: false,
      url: url,
      error: "Failed to capture page: #{e.message}",
      error_type: "job_error"
    })

    raise # Re-raise to trigger retry logic
  end

  private

  def check_cache
    cache_key = "web_capture:#{Digest::MD5.hexdigest(@url)}"
    cached = Rails.cache.read(cache_key)

    return nil unless cached

    # Verify screenshot URL is still valid (S3 URLs don't expire with public-read ACL)
    cached
  end

  def cache_result(result)
    cache_key = "web_capture:#{Digest::MD5.hexdigest(@url)}"
    # Cache for 1 hour
    Rails.cache.write(cache_key, result, expires_in: 1.hour)
  end

  def store_capture_record(result)
    # Store in WebPageCapture model if it exists
    if defined?(WebPageCapture) && WebPageCapture.respond_to?(:create)
      WebPageCapture.create(
        entity_id: @entity_id,
        user_id: @user_id,
        url: @url,
        title: result[:title],
        screenshot_url: result[:screenshot_url],
        text_content: result[:text_content],
        captured_at: Time.current
      )
    end
  rescue StandardError => e
    # Non-critical - log but don't fail
    Rails.logger.warn "[CaptureWebPageJob] Failed to store capture record: #{e.message}"
  end

  def broadcast_result(result)
    # Build canvas data for the web_page_viewer
    canvas_data = {
      url: @url,
      request_id: @canvas_request_id,
      captured_at: Time.current.iso8601
    }

    if result[:success]
      canvas_data.merge!(
        status: "complete",
        title: result[:title],
        meta_description: result[:meta_description],
        text_content: result[:text_content],
        screenshot_url: result[:screenshot_url]
      )
    else
      canvas_data.merge!(
        status: "error",
        error: result[:error],
        error_type: result[:error_type]
      )
    end

    # Broadcast via ActionCable if available
    if defined?(ActionCable) && ActionCable.server.respond_to?(:broadcast)
      channel_name = "scout_canvas_#{@entity_id}_#{@user_id}"

      ActionCable.server.broadcast(channel_name, {
        type: "canvas_update",
        canvas: "web_page_viewer",
        canvas_data: canvas_data
      })

      Rails.logger.info "[CaptureWebPageJob] Broadcast to #{channel_name}"
    end

    # Also update the task session if provided
    update_task_session(canvas_data) if @task_session_id
  end

  def update_task_session(canvas_data)
    task_session = TaskSession.find_by(id: @task_session_id)
    return unless task_session

    # Store the capture result in the task session's wizard_data
    wizard_data = task_session.wizard_data || {}
    wizard_data["web_page_captures"] ||= {}
    wizard_data["web_page_captures"][@url] = canvas_data

    task_session.update(wizard_data: wizard_data)
  rescue StandardError => e
    Rails.logger.warn "[CaptureWebPageJob] Failed to update task session: #{e.message}"
  end
end
