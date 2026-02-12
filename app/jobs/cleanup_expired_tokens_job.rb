class CleanupExpiredTokensJob < ApplicationJob
  queue_as :default

  def perform
    # Clear expired API keys
    User.where('api_key_expires_at < ?', Time.current)
        .update_all(api_key: nil, api_key_expires_at: nil)

    # Clear expired refresh tokens
    User.where('refresh_token_expires_at < ?', Time.current)
        .update_all(refresh_token: nil, refresh_token_expires_at: nil)

    Rails.logger.info "Cleaned up expired tokens"
  end
end
