# frozen_string_literal: true

require 'test_helper'

class Webhooks::GithubControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  WEBHOOK_PATH = '/webhooks/github'

  setup do
    @webhook_secret = 'test_webhook_secret_12345'
    ENV['GITHUB_WEBHOOK_SECRET'] = @webhook_secret
  end

  teardown do
    ENV.delete('GITHUB_WEBHOOK_SECRET')
  end

  test "rejects requests without signature" do
    post WEBHOOK_PATH,
      params: { action: 'opened' }.to_json,
      headers: { 'Content-Type' => 'application/json', 'X-GitHub-Event' => 'ping' }

    assert_response :unauthorized
  end

  test "rejects requests with invalid signature" do
    post WEBHOOK_PATH,
      params: { zen: 'test' }.to_json,
      headers: { 'Content-Type' => 'application/json', 'X-GitHub-Event' => 'ping', 'X-Hub-Signature-256' => 'sha256=bad' }

    assert_response :unauthorized
  end

  test "accepts requests with valid signature" do
    body = { zen: 'Keep it logically awesome.' }.to_json
    signature = sign(body)

    assert_enqueued_with(job: GithubWebhookJob) do
      post WEBHOOK_PATH, params: body,
        headers: { 'Content-Type' => 'application/json', 'X-GitHub-Event' => 'ping',
                    'X-GitHub-Delivery' => SecureRandom.uuid, 'X-Hub-Signature-256' => signature }
    end

    assert_response :ok
  end

  test "queues job for pull_request event" do
    body = build_pr_event_body.to_json

    assert_enqueued_with(job: GithubWebhookJob) do
      post WEBHOOK_PATH, params: body,
        headers: webhook_headers('pull_request', sign(body))
    end

    assert_response :ok
  end

  test "skips signature check when no secret configured in test" do
    ENV.delete('GITHUB_WEBHOOK_SECRET')
    body = { zen: 'No secret' }.to_json

    assert_enqueued_with(job: GithubWebhookJob) do
      post WEBHOOK_PATH, params: body,
        headers: { 'Content-Type' => 'application/json', 'X-GitHub-Event' => 'ping', 'X-GitHub-Delivery' => SecureRandom.uuid }
    end

    assert_response :ok
  end

  private

  def sign(body)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', @webhook_secret, body)}"
  end

  def webhook_headers(event, signature)
    { 'Content-Type' => 'application/json', 'X-GitHub-Event' => event,
      'X-GitHub-Delivery' => SecureRandom.uuid, 'X-Hub-Signature-256' => signature }
  end

  def build_pr_event_body
    { action: 'opened', pull_request: { number: 99, html_url: 'https://github.com/test/repo/pull/99',
      title: 'Test PR', body: '', merged: false, head: { ref: 'fix/test' }, user: { login: 'testuser' } },
      repository: { full_name: 'test/repo', name: 'repo' } }
  end
end
