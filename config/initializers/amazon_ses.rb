require 'aws-sdk-ses'

# Register the SES delivery method
ActionMailer::Base.add_delivery_method(:ses, 
  Class.new do
    attr_accessor :settings

    def initialize(settings)
      self.settings = settings
    end

    def deliver!(mail)
      to = Array(mail.to)
      from = mail.from.first

      # Create a new SES client
      ses = Aws::SES::Client.new(
        region: ENV['AWS_REGION'] || 'us-east-1',
        credentials: Aws::Credentials.new(
          ENV['AWS_ACCESS_KEY_ID'],
          ENV['AWS_SECRET_ACCESS_KEY']
        )
      )

      # Build the raw message
      ses.send_raw_email(
        source: from || ENV['AWS_SES_SENDER'],
        destinations: to,
        raw_message: {
          data: mail.to_s
        }
      )
    end
  end,
  settings = {}
) 