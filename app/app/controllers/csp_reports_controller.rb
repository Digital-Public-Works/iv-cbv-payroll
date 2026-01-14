class CspReportsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :redirect_if_maintenance_mode

  def create
    report = parse_csp_report
    if report.blank?
      Rails.logger.error("[CSP Report] Received malformed or empty CSP report")
      return head :bad_request
    end

    # Log to New Relic as a custom event
    NewRelic::Agent.record_custom_event("CSPViolation", {
      document_uri: report["document-uri"],
      violated_directive: report["violated-directive"],
      blocked_uri: report["blocked-uri"],
      source_file: report["source-file"],
      line_number: report["line-number"],
      column_number: report["column-number"],
      original_policy: report["original-policy"]&.truncate(500)
    })

    # Also log to Rails logger for visibility
    Rails.logger.fatal("[CSP Violation] #{report['violated-directive']} - blocked: #{report['blocked-uri']}")

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
end
