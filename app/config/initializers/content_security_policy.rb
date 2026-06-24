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
    policy.img_src :self, :data, "https://*.cloudinary.com", "https://cdn.getpinwheel.com", "https://static.verifymyincome.org"
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

    # Allow inline <style> tags injected by the Aggregator SDKs (Pinwheel and
    # Argyle).
    #
    # We previously pinned each SDK's inline <style> by SHA-256 hash, but the
    # Argyle web SDK (argyle.web.v5.js) injects dynamically-generated style
    # content whose hash changes between renders, so hash-pinning is no longer
    # viable. A nonce can't help either: the SDKs inject their own <style> tags
    # from CDN code and cannot stamp our per-request nonce on them.
    #
    # 'unsafe-inline' is therefore required for style-src. Note this relaxes
    # style injection protection ONLY; script-src remains strict (nonces +
    # explicit hosts). Per CSP spec, mixing 'unsafe-inline' with hashes/nonces
    # makes browsers ignore 'unsafe-inline', so the SDK style hashes are removed.
    policy.style_src :self, :unsafe_inline

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
