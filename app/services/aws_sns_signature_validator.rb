class AwsSnsSignatureValidator
  # Verify SNS message signature
  # https://docs.aws.amazon.com/sns/latest/dg/sns-verify-signature-of-message.html
  def self.verify!(request_body, request_headers)
    message = JSON.parse(request_body)

    # Verify required fields
    validate_message_structure!(message)

    # Build signature string
    signature_string = build_signature_string(message)

    # Decode signature
    signature = Base64.decode64(message['Signature'])

    # Get signing certificate
    cert = get_certificate(message['SigningCertURL'])

    # Verify signature using certificate public key
    verified = cert.public_key.verify(
      OpenSSL::Digest::SHA1.new,
      signature,
      signature_string
    )

    raise InvalidSignatureError, 'SNS signature verification failed' unless verified

    true
  rescue JSON::ParserError => e
    raise InvalidMessageError, "Invalid JSON: #{e.message}"
  end

  private

  def self.validate_message_structure!(message)
    required_fields = %w[Type MessageId Timestamp Signature SignatureVersion SigningCertURL]

    required_fields.each do |field|
      raise InvalidMessageError, "Missing required field: #{field}" unless message[field].present?
    end

    # Validate SignatureVersion
    unless message['SignatureVersion'] == '1'
      raise InvalidMessageError, "Unsupported signature version: #{message['SignatureVersion']}"
    end

    # Validate SigningCertURL is from AWS
    cert_url = URI.parse(message['SigningCertURL'])
    unless cert_url.scheme == 'https' && cert_url.host.end_with?('.amazonaws.com')
      raise InvalidCertificateError, 'Invalid signing certificate URL'
    end
  end

  def self.build_signature_string(message)
    # Fields to include in signature vary by message type
    fields = if message['Type'] == 'Notification'
      %w[Message MessageId Subject Timestamp TopicArn Type]
    elsif message['Type'] == 'SubscriptionConfirmation' || message['Type'] == 'UnsubscribeConfirmation'
      %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type]
    else
      raise InvalidMessageError, "Unknown message type: #{message['Type']}"
    end

    # Build string to sign (fields in alphabetical order)
    fields.sort.map { |field|
      next unless message[field].present?
      "#{field}\n#{message[field]}\n"
    }.compact.join
  end

  def self.get_certificate(cert_url)
    # Cache certificates to avoid repeated downloads
    @certs ||= {}

    return @certs[cert_url] if @certs[cert_url]

    # Download certificate with timeout
    response = Faraday.get(cert_url) do |req|
      req.options.timeout = 5
      req.options.open_timeout = 2
    end

    raise InvalidCertificateError, 'Failed to download certificate' unless response.success?

    cert = OpenSSL::X509::Certificate.new(response.body)

    # Verify certificate is from AWS
    unless cert.subject.to_s.include?('Amazon')
      raise InvalidCertificateError, 'Certificate not from Amazon'
    end

    @certs[cert_url] = cert
    cert
  rescue Faraday::Error => e
    raise InvalidCertificateError, "Certificate download failed: #{e.message}"
  end

  # Custom error classes
  class InvalidSignatureError < StandardError; end
  class InvalidMessageError < StandardError; end
  class InvalidCertificateError < StandardError; end
end
