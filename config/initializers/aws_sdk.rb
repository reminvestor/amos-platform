require "aws-sdk-rails"

# Ensure the delivery method is registered immediately
ActionMailer::Base.add_delivery_method :aws_sdk, Aws::Rails::Mailer

