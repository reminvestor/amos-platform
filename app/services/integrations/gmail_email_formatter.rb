# frozen_string_literal: true

module Integrations
  # Formats email parameters into RFC 2822 format with base64url encoding
  # as required by Gmail's API
  class GmailEmailFormatter
    # Convert simple email parameters to Gmail's required format
    # @param params [Hash] Email parameters (to, subject, body, cc, bcc, from, reply_to)
    # @return [Hash] Gmail API format with base64url encoded raw message
    def self.format(params)
      raw_message = build_rfc2822_message(params)
      encoded = base64url_encode(raw_message)
      
      { "raw" => encoded }
    end

    # Build an RFC 2822 compliant email message
    # @param params [Hash] Email parameters
    # @return [String] RFC 2822 formatted message
    def self.build_rfc2822_message(params)
      to = params[:to] || params["to"]
      subject = params[:subject] || params["subject"]
      body = params[:body] || params["body"]
      cc = params[:cc] || params["cc"]
      bcc = params[:bcc] || params["bcc"]
      from = params[:from] || params["from"]
      reply_to = params[:reply_to] || params["reply_to"]
      content_type = params[:content_type] || params["content_type"] || "text/plain"
      
      # Determine if body is HTML
      is_html = content_type.include?("html") || body&.include?("<html") || body&.include?("<body")
      content_type = is_html ? "text/html; charset=UTF-8" : "text/plain; charset=UTF-8"
      
      # Build headers
      headers = []
      headers << "MIME-Version: 1.0"
      headers << "Content-Type: #{content_type}"
      headers << "To: #{normalize_recipients(to)}"
      headers << "Cc: #{normalize_recipients(cc)}" if cc.present?
      headers << "Bcc: #{normalize_recipients(bcc)}" if bcc.present?
      headers << "From: #{from}" if from.present?
      headers << "Reply-To: #{reply_to}" if reply_to.present?
      headers << "Subject: #{encode_subject(subject)}"
      headers << "Date: #{Time.current.rfc2822}"
      headers << "Message-ID: <#{SecureRandom.uuid}@amoslabs.com>"
      
      # Combine headers and body with blank line separator
      "#{headers.join("\r\n")}\r\n\r\n#{body}"
    end

    # Base64url encode (Gmail requires URL-safe base64 without padding)
    # @param string [String] The string to encode
    # @return [String] Base64url encoded string
    def self.base64url_encode(string)
      Base64.urlsafe_encode64(string, padding: false)
    end

    # Normalize recipients to comma-separated string
    # @param recipients [String, Array] Recipients
    # @return [String] Comma-separated recipients
    def self.normalize_recipients(recipients)
      return "" if recipients.blank?
      
      case recipients
      when Array
        recipients.map(&:strip).join(", ")
      when String
        recipients.strip
      else
        recipients.to_s.strip
      end
    end

    # Encode subject for RFC 2822 (handles non-ASCII characters)
    # @param subject [String] The subject line
    # @return [String] Encoded subject
    def self.encode_subject(subject)
      return "" if subject.blank?
      
      # If subject contains non-ASCII, encode it
      if subject.ascii_only?
        subject
      else
        # Use RFC 2047 encoded-word syntax for non-ASCII
        "=?UTF-8?B?#{Base64.strict_encode64(subject)}?="
      end
    end

    # Check if params need transformation (simple format vs raw)
    # @param params [Hash] The parameters
    # @return [Boolean] True if needs transformation
    def self.needs_transformation?(params)
      # If it has 'raw' key, it's already in Gmail format
      return false if params.key?("raw") || params.key?(:raw)
      
      # If it has simple email fields, needs transformation
      params.key?("to") || params.key?(:to) ||
        params.key?("subject") || params.key?(:subject) ||
        params.key?("body") || params.key?(:body)
    end
  end
end

