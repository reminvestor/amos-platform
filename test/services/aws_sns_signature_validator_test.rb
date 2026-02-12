require "test_helper"

class AwsSnsSignatureValidatorTest < ActiveSupport::TestCase
  # Story 0.6: AWS SNS Signature Verification Tests

  test "rejects message with missing required fields" do
    message = {
      "Type" => "Notification"
      # Missing MessageId, Timestamp, Signature, etc.
    }

    assert_raises(AwsSnsSignatureValidator::InvalidMessageError) do
      AwsSnsSignatureValidator.verify!(message.to_json, {})
    end
  end

  test "rejects message with invalid signature version" do
    message = {
      "Type" => "Notification",
      "MessageId" => "12345",
      "Timestamp" => Time.current.iso8601,
      "Signature" => "fake",
      "SignatureVersion" => "2",  # Invalid - only "1" is supported
      "SigningCertURL" => "https://sns.us-east-1.amazonaws.com/cert.pem"
    }

    error = assert_raises(AwsSnsSignatureValidator::InvalidMessageError) do
      AwsSnsSignatureValidator.verify!(message.to_json, {})
    end

    assert_includes error.message, "Unsupported signature version"
  end

  test "rejects message with non-AWS certificate URL" do
    message = {
      "Type" => "Notification",
      "MessageId" => "12345",
      "Timestamp" => Time.current.iso8601,
      "Signature" => "fake",
      "SignatureVersion" => "1",
      "SigningCertURL" => "https://evil.com/cert.pem"  # Not from amazonaws.com
    }

    error = assert_raises(AwsSnsSignatureValidator::InvalidCertificateError) do
      AwsSnsSignatureValidator.verify!(message.to_json, {})
    end

    assert_includes error.message, "Invalid signing certificate URL"
  end

  test "rejects message with HTTP certificate URL" do
    message = {
      "Type" => "Notification",
      "MessageId" => "12345",
      "Timestamp" => Time.current.iso8601,
      "Signature" => "fake",
      "SignatureVersion" => "1",
      "SigningCertURL" => "http://sns.us-east-1.amazonaws.com/cert.pem"  # HTTP not HTTPS
    }

    error = assert_raises(AwsSnsSignatureValidator::InvalidCertificateError) do
      AwsSnsSignatureValidator.verify!(message.to_json, {})
    end

    assert_includes error.message, "Invalid signing certificate URL"
  end

  test "rejects message with invalid JSON" do
    invalid_json = "{ this is not valid json"

    error = assert_raises(AwsSnsSignatureValidator::InvalidMessageError) do
      AwsSnsSignatureValidator.verify!(invalid_json, {})
    end

    assert_includes error.message, "Invalid JSON"
  end

  test "builds correct signature string for Notification messages" do
    message = {
      "Type" => "Notification",
      "MessageId" => "12345",
      "Message" => "Test message",
      "Subject" => "Test subject",
      "Timestamp" => "2026-02-11T00:00:00Z",
      "TopicArn" => "arn:aws:sns:us-east-1:123456789012:test-topic"
    }

    signature_string = AwsSnsSignatureValidator.send(:build_signature_string, message)

    # Signature string should include fields in alphabetical order
    assert_includes signature_string, "Message\n"
    assert_includes signature_string, "MessageId\n"
    assert_includes signature_string, "Subject\n"
    assert_includes signature_string, "Timestamp\n"
    assert_includes signature_string, "TopicArn\n"
    assert_includes signature_string, "Type\n"
  end

  test "builds correct signature string for SubscriptionConfirmation messages" do
    message = {
      "Type" => "SubscriptionConfirmation",
      "MessageId" => "12345",
      "Message" => "Confirm subscription",
      "SubscribeURL" => "https://sns.us-east-1.amazonaws.com/...",
      "Timestamp" => "2026-02-11T00:00:00Z",
      "Token" => "token123",
      "TopicArn" => "arn:aws:sns:us-east-1:123456789012:test-topic"
    }

    signature_string = AwsSnsSignatureValidator.send(:build_signature_string, message)

    # Should include subscription-specific fields
    assert_includes signature_string, "SubscribeURL\n"
    assert_includes signature_string, "Token\n"
    # Should NOT include Subject (not part of subscription confirmation)
    assert_not_includes signature_string, "Subject\n"
  end

  test "rejects message with unknown type" do
    message = {
      "Type" => "UnknownType",
      "MessageId" => "12345"
    }

    error = assert_raises(AwsSnsSignatureValidator::InvalidMessageError) do
      AwsSnsSignatureValidator.send(:build_signature_string, message)
    end

    assert_includes error.message, "Unknown message type"
  end

  test "certificate download has timeout protection" do
    message = {
      "Type" => "Notification",
      "MessageId" => "12345",
      "Timestamp" => Time.current.iso8601,
      "Signature" => Base64.encode64("fake_signature"),
      "SignatureVersion" => "1",
      "SigningCertURL" => "https://sns.us-east-1.amazonaws.com/timeout-test.pem",
      "Message" => "Test",
      "TopicArn" => "arn:aws:sns:us-east-1:123456789012:test"
    }

    # Mock Faraday to simulate timeout
    Faraday.stub(:get, ->(*args) { raise Faraday::TimeoutError.new("Timeout") }) do
      error = assert_raises(AwsSnsSignatureValidator::InvalidCertificateError) do
        AwsSnsSignatureValidator.verify!(message.to_json, {})
      end

      assert_includes error.message, "Certificate download failed"
    end
  end

  test "certificates are cached in Rails.cache" do
    cert_url = "https://sns.us-east-1.amazonaws.com/cached-cert.pem"
    cache_key = "sns_cert:#{Digest::SHA256.hexdigest(cert_url)}"

    # Clear cache
    Rails.cache.delete(cache_key)

    # Create a mock certificate
    mock_cert = OpenSSL::X509::Certificate.new
    mock_cert.subject = OpenSSL::X509::Name.new([["CN", "Amazon SNS"]])

    # Create mock response struct
    MockResponse = Struct.new(:success?, :body)

    # Stub Faraday to return mock cert data
    Faraday.stub(:get, ->(url) {
      MockResponse.new(true, mock_cert.to_pem)
    }) do
      # First call - should fetch from network
      AwsSnsSignatureValidator.send(:get_certificate, cert_url)

      # Verify it's cached
      cached_cert = Rails.cache.read(cache_key)
      assert cached_cert.present?, "Certificate should be cached"
      assert_equal mock_cert.to_pem, cached_cert.to_pem
    end
  end

  test "certificate must be from Amazon" do
    cert_url = "https://sns.us-east-1.amazonaws.com/non-amazon-cert.pem"

    # Create certificate with non-Amazon subject
    fake_cert = OpenSSL::X509::Certificate.new
    fake_cert.subject = OpenSSL::X509::Name.new([["CN", "Evil Corp"]])

    # Create mock response struct
    MockResponse = Struct.new(:success?, :body)

    # Stub Faraday to return fake cert
    Faraday.stub(:get, ->(url) {
      MockResponse.new(true, fake_cert.to_pem)
    }) do
      error = assert_raises(AwsSnsSignatureValidator::InvalidCertificateError) do
        AwsSnsSignatureValidator.send(:get_certificate, cert_url)
      end

      assert_includes error.message, "Certificate not from Amazon"
    end
  end

  test "validates all required fields are present" do
    required_fields = %w[Type MessageId Timestamp Signature SignatureVersion SigningCertURL]

    required_fields.each do |field|
      message = {
        "Type" => "Notification",
        "MessageId" => "12345",
        "Timestamp" => Time.current.iso8601,
        "Signature" => "fake",
        "SignatureVersion" => "1",
        "SigningCertURL" => "https://sns.us-east-1.amazonaws.com/cert.pem"
      }

      # Remove one required field
      message.delete(field)

      error = assert_raises(AwsSnsSignatureValidator::InvalidMessageError) do
        AwsSnsSignatureValidator.send(:validate_message_structure!, message)
      end

      assert_includes error.message, "Missing required field: #{field}"
    end
  end

  test "signature string fields are in alphabetical order" do
    message = {
      "Type" => "Notification",
      "TopicArn" => "arn:aws:sns:us-east-1:123456789012:test",
      "MessageId" => "12345",
      "Message" => "Test",
      "Timestamp" => "2026-02-11T00:00:00Z"
    }

    signature_string = AwsSnsSignatureValidator.send(:build_signature_string, message)

    # Fields should appear in order: Message, MessageId, Timestamp, TopicArn, Type
    fields_order = signature_string.scan(/^([A-Z][a-z]+)\n/).flatten

    assert_equal fields_order, fields_order.sort,
                 "Signature string fields should be in alphabetical order"
  end
end
