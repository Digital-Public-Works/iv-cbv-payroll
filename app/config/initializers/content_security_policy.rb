# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src :self, "https://*.cloudinary.com"
    policy.form_action :self, "https://login.microsoftonline.com"
    policy.frame_ancestors :self
    policy.img_src :self, :data, "https://*.cloudinary.com", "https://cdn.getpinwheel.com"
    policy.object_src :none
    policy.script_src :self, *%w[
      https://js-agent.newrelic.com
      https://*.nr-data.net
      https://cdn.getpinwheel.com
      https://*.argyle.com
    ]
    policy.connect_src :self, "https://*.nr-data.net", "https://*.argyle.com"
    policy.worker_src :self, "blob:"
    policy.frame_src :self, "https://cdn.getpinwheel.com"

    # Argyle and Pinwheel SDKs inject dynamic inline styles that change across
    # versions, making hash-based CSP impractical. Using 'unsafe-inline' for
    # styles is acceptable as style injection is lower risk than script injection.
    policy.style_src :self, :unsafe_inline

    # Report CSP violations to New Relic
    policy.report_uri "/csp-reports"
  end

  #
  #   # Generate session nonces for permitted importmap and inline scripts
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
  #
  #   # Report violations without enforcing the policy.
  #   # config.content_security_policy_report_only = true
end
