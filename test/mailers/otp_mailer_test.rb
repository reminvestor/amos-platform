# frozen_string_literal: true

require "test_helper"

class OtpMailerTest < ActionMailer::TestCase
  def setup
    @user = users(:one)
    @code = "123456"
  end

  test "send_otp sends email to user" do
    email = OtpMailer.send_otp(@user, @code)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@user.email], email.to
  end

  test "send_otp includes code in subject" do
    email = OtpMailer.send_otp(@user, @code)
    assert_includes email.subject, @code
  end

  test "send_otp includes code in body" do
    email = OtpMailer.send_otp(@user, @code)
    assert_includes email.body.to_s, @code
  end

  test "send_otp includes user first name" do
    email = OtpMailer.send_otp(@user, @code)
    assert_includes email.body.to_s, @user.first_name
  end

  test "send_otp includes expiry warning" do
    email = OtpMailer.send_otp(@user, @code)
    assert_match /5 minutes|expires/i, email.body.to_s
  end

  test "send_otp has proper from address" do
    email = OtpMailer.send_otp(@user, @code)
    assert_not_nil email.from
  end

  test "send_otp includes security notice" do
    email = OtpMailer.send_otp(@user, @code)
    # Check for security-related content
    assert_match /didn't request|ignore/i, email.body.to_s
  end
end
