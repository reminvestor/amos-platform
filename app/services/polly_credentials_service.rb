# PollyCredentialsService generates temporary AWS credentials for client-side Polly access
#
# Responsibilities:
# - Generate temporary STS credentials scoped to Polly:SynthesizeSpeech
# - Provide voice configuration for client
# - Log credential usage for audit trail
#
# Usage:
#   service = PollyCredentialsService.new(voice_session)
#   creds = service.generate_credentials(ttl_minutes: 15)
class PollyCredentialsService
  DEFAULT_TTL_MINUTES = 15
  DEFAULT_VOICE_ID = "Matthew".freeze
  DEFAULT_ENGINE = "neural".freeze
  DEFAULT_OUTPUT_FORMAT = "pcm".freeze
  DEFAULT_SAMPLE_RATE = "16000".freeze

  attr_reader :voice_session

  def initialize(voice_session)
    @voice_session = voice_session
  end

  # Generate temporary AWS credentials for Polly access
  #
  # @param ttl_minutes [Integer] Time-to-live in minutes (default: 15)
  # @return [Hash] Temporary credentials and voice configuration
  def generate_credentials(ttl_minutes: DEFAULT_TTL_MINUTES)
    sts_client = Aws::STS::Client.new(region: aws_region)

    # Get temporary credentials via STS AssumeRole or GetFederationToken
    response = sts_client.get_federation_token({
      name: "voice-session-#{voice_session.session_id}",
      duration_seconds: ttl_minutes * 60,
      policy: iam_policy.to_json
    })

    credentials = response.credentials

    log_credential_generation(credentials)

    {
      access_key_id: credentials.access_key_id,
      secret_access_key: credentials.secret_access_key,
      session_token: credentials.session_token,
      region: aws_region,
      expiration: credentials.expiration,
      voice_config: voice_config
    }
  rescue Aws::STS::Errors::ServiceError => e
    Rails.logger.error "AWS STS error: #{e.message}"
    raise "Failed to generate Polly credentials: #{e.message}"
  end

  # Get voice configuration for client
  #
  # @return [Hash] Voice configuration
  def voice_config
    {
      voice_id: DEFAULT_VOICE_ID,
      engine: DEFAULT_ENGINE,
      output_format: DEFAULT_OUTPUT_FORMAT,
      sample_rate: DEFAULT_SAMPLE_RATE,
      speech_mark_types: %w[word sentence]
    }
  end

  private

  def aws_region
    ENV["AWS_REGION"] || "us-east-1"
  end

  # Generate IAM policy scoped to Polly:SynthesizeSpeech only
  #
  # @return [Hash] IAM policy document
  def iam_policy
    {
      Version: "2012-10-17",
      Statement: [
        {
          Effect: "Allow",
          Action: [
            "polly:SynthesizeSpeech"
          ],
          Resource: "*",
          Condition: {
            StringEquals: {
              "aws:RequestedRegion": aws_region
            }
          }
        }
      ]
    }
  end

  def log_credential_generation(credentials)
    Rails.logger.info({
      event: "polly_credentials_generated",
      session_id: voice_session.session_id,
      entity_id: voice_session.entity_id,
      user_id: voice_session.user_id,
      access_key_id: credentials.access_key_id,
      expires_at: credentials.expiration
    }.to_json)
  end
end
