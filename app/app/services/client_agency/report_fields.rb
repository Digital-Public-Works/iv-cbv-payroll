class ClientAgency::ReportFields
  extend ReportViewHelper

  def self.caseworker_specific_fields(cbv_flow)
    agency = ClientAgencyConfig.instance[cbv_flow.client_agency_id]
    agency.applicant_attributes
      .select { |_name, attr| attr.show_on_caseworker_report }
      .map { |name, _attr| [ ".pdf.caseworker.#{name}", cbv_flow.cbv_applicant.send(name) ] }
  end

  # The other jobs answer is client-provided, so its label carries the footnote
  # marker. Any partner that asks the question also shows the footnote legend
  # (see ClientAgency#collects_client_provided_information?).
  def self.applicant_specific_fields(cbv_flow)
    agency = ClientAgencyConfig.instance[cbv_flow.client_agency_id]
    return [] unless agency.allow_outside_jobs

    [
      [ ".pdf.shared.additional_jobs_to_report_html", format_boolean(cbv_flow.has_other_jobs) ]
    ]
  end
end
