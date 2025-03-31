# Make sure all Heroku requests come through as SSL since Heroku terminates SSL
# but the request still needs to be recognized as HTTPS by Rails

if Rails.env.production?
  # Tell Rails to respect the X-Forwarded-Proto header
  Rails.application.config.after_initialize do
    ActionController::Base.class_eval do
      def self.default_url_options
        { protocol: 'https' }
      end
    end
  end
end 