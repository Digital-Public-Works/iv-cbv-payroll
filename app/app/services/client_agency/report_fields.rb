class ClientAgency::ReportFields
  extend ReportViewHelper

  def self.caseworker_specific_fields(cbv_flow)
    agency = ClientAgencyConfig.instance[cbv_flow.client_agency_id]
    agency.applicant_attributes
      .select { |_name, attr| attr.show_on_caseworker_report }
      .map { |name, _attr| [ ".pdf.caseworker.#{name}", cbv_flow.cbv_applicant.send(name) ] }
  end

  def self.applicant_specific_fields(cbv_flow)
    [
      [ additional_jobs_to_report_string(cbv_flow), format_boolean(cbv_flow.has_other_jobs) ]
    ]
  end

  private

  def self.additional_jobs_to_report_string(cbv_flow)
    if cbv_flow.cbv_applicant.applicant_attributes.present?
      ".pdf.shared.additional_jobs_to_report_html" # render with <sup> tag
    else
      ".pdf.shared.additional_jobs_to_report"
    end
  end
end
