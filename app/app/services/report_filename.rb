# frozen_string_literal: true

# Canonical report filename stem shared between transmitters that name
# files on disk (S3, SFTP via override) and any structured outputs that
# need to advertise filenames downstream (CbvFlowToJson for webhooks).
#
# Format:
#   IncomeReport_<partner_identifier>_<MonStart>-<MonEnd><Year>_Conf<code>_<YYYYmmddHHMMSS>
module ReportFilename
  module_function

  def stem(cbv_flow, aggregator_report, at: Time.now)
    beginning_date = aggregator_report.from_date.to_date.strftime("%b")
    ending_date = aggregator_report.to_date.to_date.strftime("%b%Y")
    "IncomeReport_#{cbv_flow.cbv_applicant.partner_identifier}_" \
      "#{beginning_date}-#{ending_date}_" \
      "Conf#{cbv_flow.confirmation_code}_" \
      "#{at.strftime('%Y%m%d%H%M%S')}"
  end

  def paystubs_filename(stem)
    "#{stem}_paystubs.pdf"
  end

  def report_filename(stem)
    "#{stem}.pdf"
  end
end
