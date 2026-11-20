class CspReportsController < ApplicationController
  skip_forgery_protection
  skip_before_action :redirect_if_maintenance_mode

  # browser-injected items are not actionable
  BROWSER_EXTENSION_SCHEMES = %w[
    chrome-extension
    moz-extension
    safari-extension
    safari-web-extension
    ms-browser-extension
  ].freeze

  # blocked images from browser extensions are not relevant to us
  IGNORED_DIRECTIVES = %w[img-src].freeze

  # extra items sent by argle, we do not need to track that we are blocking them
  ARGYLE_SDK_SOURCE_PREFIX = "https://plugin.argyle.com/".freeze

  def create
    report = parse_csp_report
    if report.blank?
      Rails.logger.error("[CSP Report] Received malformed or empty CSP report")
      return head :bad_request
    end

    directive = directive_name(report)

    if (reason = ignore_reason(report, directive))
      Rails.logger.info("[CSP Violation ignored: #{reason}] #{report['violated-directive']} - blocked: #{report['blocked-uri']}")
      return head :no_content
    end

    # omit original-policy - it is large, identical in each report, and gives us no useful info
    NewRelic::EventLogger.track(TrackEvent::CSPViolation, {
      document_uri: report["document-uri"],
      violated_directive: report["violated-directive"],
      blocked_uri: report["blocked-uri"],
      source_file: report["source-file"],
      line_number: report["line-number"],
      column_number: report["column-number"]
    })

    # Also log to Rails logger for visibility
    Rails.logger.warn("[CSP Violation] #{report['violated-directive']} - blocked: #{report['blocked-uri']}")

    head :no_content
  end

  private

  def parse_csp_report
    body = request.body.read
    JSON.parse(body).fetch("csp-report", nil)
  rescue JSON::ParserError => e
    Rails.logger.error("[CSP Report] JSON parse error: #{e.message}, body: #{body&.truncate(500)}")
    nil
  end

  # older browser guard
  def directive_name(report)
    (report["effective-directive"].presence || report["violated-directive"].to_s).split.first.to_s
  end

  def ignore_reason(report, directive)
    if browser_extension?(report["blocked-uri"]) || browser_extension?(report["source-file"])
      "browser extension"
    elsif IGNORED_DIRECTIVES.include?(directive)
      directive
    elsif directive == "script-src-attr" && report["source-file"].to_s.start_with?(ARGYLE_SDK_SOURCE_PREFIX)
      "argyle sdk inline handler"
    end
  end

  def browser_extension?(uri)
    return false if uri.blank?

    BROWSER_EXTENSION_SCHEMES.any? { |scheme| uri == scheme || uri.start_with?("#{scheme}:") }
  end
end
