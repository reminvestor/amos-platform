#!/usr/bin/env ruby
require_relative 'config/environment'
require 'ostruct'

puts "Running email test..."

# Find a user
user = User.first
puts "Using user: #{user.email}"

# Find or create a template
template = user.email_templates.first
if template.nil?
  puts "No template found, creating one..."
  template = user.email_templates.create!(
    name: "Test Template",
    subject: "Test Email Subject",
    body: "<p>Hello {{first_name}},</p><p>This is a test email.</p>"
  )
else
  puts "Using template: #{template.name}"
end

# Create a test contact
puts "Creating test contact..."
test_email = "rick@nuvola-networks.com"  # Your actual email
test_contact = OpenStruct.new(
  first_name: "Test",
  last_name: "User",
  email: test_email
)

puts "Email configuration:"
puts "Delivery method: #{ActionMailer::Base.delivery_method}"
puts "Perform deliveries: #{ActionMailer::Base.perform_deliveries}"
puts "AWS Region: #{ENV['AWS_REGION'] || 'Not set'}"
puts "AWS Access Key ID: #{ENV['AWS_ACCESS_KEY_ID'] ? 'Present' : 'Missing'}"
puts "AWS Secret Access Key: #{ENV['AWS_SECRET_ACCESS_KEY'] ? 'Present' : 'Missing'}"
puts "AWS SES Sender: #{ENV['AWS_SES_SENDER'] || 'Not set'}"

begin
  puts "Sending test email to #{test_email}..."
  mail = TestEmailMailer.template_test(template, test_contact, user)
  result = mail.deliver_now
  puts "Email sent! Delivery result: #{result.inspect}"
rescue => e
  puts "Error sending email: #{e.message}"
  puts e.backtrace.join("\n")
end

puts "Test completed."
