require "test_helper"

class UserSecurityTest < ActiveSupport::TestCase
  # Story 0.1: Account Lockout Tests
  test "account locks after 5 failed login attempts" do
    user = users(:one)

    5.times { user.increment_failed_login! }
    assert user.account_locked?, "Account should be locked after 5 failed attempts"
    assert_equal 5, user.failed_login_attempts
  end

  test "account unlocks after 30 minutes" do
    user = users(:one)
    5.times { user.increment_failed_login! }

    # Simulate 31 minutes passing
    travel 31.minutes do
      assert_not user.account_locked?, "Account should unlock after 30 minutes"
    end
  end

  test "reset_failed_login! clears lockout state" do
    user = users(:one)
    5.times { user.increment_failed_login! }

    user.reset_failed_login!
    assert_equal 0, user.failed_login_attempts
    assert_nil user.last_failed_login_at
    assert_not user.account_locked?
  end

  test "unlock_account! resets failed attempts" do
    user = users(:one)
    5.times { user.increment_failed_login! }

    user.unlock_account!
    assert_not user.account_locked?
  end

  # Story 0.3: Password Complexity Tests
  test "password must contain lowercase letter" do
    user = User.new(email: 'test@example.com', password: 'PASSWORD123!', entity: entities(:one))
    assert_not user.valid?
    assert_includes user.errors[:password], 'must contain at least one lowercase letter'
  end

  test "password must contain uppercase letter" do
    user = User.new(email: 'test@example.com', password: 'password123!', entity: entities(:one))
    assert_not user.valid?
    assert_includes user.errors[:password], 'must contain at least one uppercase letter'
  end

  test "password must contain digit" do
    user = User.new(email: 'test@example.com', password: 'Password!', entity: entities(:one))
    assert_not user.valid?
    assert_includes user.errors[:password], 'must contain at least one digit'
  end

  test "password must contain special character" do
    user = User.new(email: 'test@example.com', password: 'Password123', entity: entities(:one))
    assert_not user.valid?
    assert_includes user.errors[:password], 'must contain at least one special character (!@#$%^&*()_+-=[]{}|;:,.<>?)'
  end

  test "password cannot contain whitespace" do
    user = User.new(email: 'test@example.com', password: 'Pass word123!', entity: entities(:one))
    assert_not user.valid?
    assert_includes user.errors[:password], 'cannot contain whitespace'
  end

  test "password cannot be too common" do
    user = User.new(email: 'test@example.com', password: 'password', entity: entities(:one))
    assert_not user.valid?
    assert_includes user.errors[:password], 'is too common. Please choose a more unique password.'
  end

  test "valid complex password is accepted" do
    user = User.new(
      email: 'test@example.com',
      password: 'MyS3cur3P@ssw0rd!',
      first_name: 'Test',
      last_name: 'User',
      entity: entities(:one)
    )
    assert user.valid?, "Complex password should be valid: #{user.errors.full_messages.join(', ')}"
  end

  # Story 0.4: API Key Expiration Tests
  test "generate_api_key! sets expiration to 90 days" do
    user = users(:one)
    user.generate_api_key!

    assert user.api_key.present?
    assert user.api_key_expires_at.present?
    assert user.api_key_expires_at > 89.days.from_now
    assert user.api_key_expires_at < 91.days.from_now
  end

  test "generate_refresh_token! sets expiration to 180 days" do
    user = users(:one)
    user.generate_refresh_token!

    assert user.refresh_token.present?
    assert user.refresh_token_expires_at.present?
    assert user.refresh_token_expires_at > 179.days.from_now
    assert user.refresh_token_expires_at < 181.days.from_now
  end

  test "api_key_expired? detects expired keys" do
    user = users(:one)
    user.update(api_key_expires_at: 1.day.ago)

    assert user.api_key_expired?, "API key should be expired"
  end

  test "api_key_expired? returns false for valid keys" do
    user = users(:one)
    user.update(api_key_expires_at: 30.days.from_now)

    assert_not user.api_key_expired?, "API key should not be expired"
  end

  test "refresh_token_valid? validates correct token" do
    user = users(:one)
    user.generate_refresh_token!
    token = user.refresh_token

    assert user.refresh_token_valid?(token), "Refresh token should be valid"
  end

  test "refresh_token_valid? rejects wrong token" do
    user = users(:one)
    user.generate_refresh_token!

    assert_not user.refresh_token_valid?('wrong_token'), "Wrong token should be rejected"
  end

  test "refresh_token_valid? rejects expired token" do
    user = users(:one)
    user.generate_refresh_token!
    user.update(refresh_token_expires_at: 1.day.ago)
    token = user.refresh_token

    assert_not user.refresh_token_valid?(token), "Expired token should be rejected"
  end

  test "touch_api_key! updates last_used_at" do
    user = users(:one)
    user.update(api_key_last_used_at: 1.hour.ago)
    old_time = user.api_key_last_used_at

    user.touch_api_key!
    user.reload

    assert user.api_key_last_used_at > old_time, "Last used timestamp should be updated"
  end

  test "generate_api_key on create sets expiration" do
    user = User.create!(
      email: 'newuser@example.com',
      password: 'MyS3cur3P@ssw0rd!',
      first_name: 'New',
      last_name: 'User',
      entity: entities(:one)
    )

    assert user.api_key.present?
    assert user.api_key_expires_at.present?
    assert user.api_key_last_used_at.present?
  end
end
