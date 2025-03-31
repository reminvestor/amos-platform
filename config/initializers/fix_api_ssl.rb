# Configure the API controller to handle HTTPS properly with Heroku
Rails.application.config.after_initialize do
  # Patch to ensure API controllers always respond with JSON
  if defined?(Api::BaseController)
    Api::BaseController.class_eval do
      # Ensure proper response format
      before_action :set_header_for_ssl
      
      private
      
      def set_header_for_ssl
        request.env['HTTPS'] = 'on'
        request.env['HTTP_X_FORWARDED_PROTO'] = 'https'
        request.env['rack.url_scheme'] = 'https'
        response.headers['Content-Type'] = 'application/json; charset=utf-8'
      end
    end
  end
end 