# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data, "https://fonts.gstatic.com", "https://cdn.jsdelivr.net"
    policy.img_src     :self, :data, :https
    policy.object_src  :none
    policy.script_src  :self, "https://unpkg.com", "https://cdn.jsdelivr.net"
    policy.style_src   :self, :unsafe_inline, "https://fonts.googleapis.com", "https://cdn.jsdelivr.net"
    policy.connect_src :self, "wss://#{ENV.fetch('APPLICATION_HOST', 'localhost:3000')}"
    policy.frame_ancestors :self
    policy.base_uri    :self
    policy.form_action :self
  end

  # Generate session nonces for permitted importmap and inline scripts.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Start in report-only mode to avoid breaking existing functionality.
  # Once validated in staging, remove this line to enforce.
  config.content_security_policy_report_only = true
end
