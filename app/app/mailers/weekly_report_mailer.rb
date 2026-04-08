require "csv"
class WeeklyReportMailer < ApplicationMailer
  helper :view

  # Send email with a CSV file that reports on completed flows in past week
  def report_email
    client_id    = params.fetch(:client_id)
    # this needs to be @report_range as it is used in the view template
    @report_range = params.fetch(:report_range)
    recipient    = params.fetch(:recipient)

    current_agency = client_agency_config[client_id]
    raise "Invalid `client_agency_id` parameter given: #{params[:client_agency_id].inspect}" unless current_agency.present?

    raise "Missing `report_range` param" unless @report_range.present?

    raise "Missing `weekly_report.recipient` configuration for client agency: #{params[:client_agency_id]}" unless recipient

    csv_rows = weekly_report_data(current_agency, @report_range)
    attachments[report_filename(@report_range)] = generate_csv(csv_rows)

    mail(
      to: recipient,
      subject: "CBV Pilot - Weekly Report Email",
    )
  end

  private

  def report_filename(report_range)
    "weekly_report_#{report_range.begin.strftime("%Y%m%d")}-#{report_range.end.strftime("%Y%m%d")}.csv"
  end

  def weekly_report_data(current_agency, report_range)
    client_agency_id = current_agency.id
    report_variant = current_agency.weekly_report["report_variant"] || "flows"

    case report_variant
    when "invitations"
      CbvFlowInvitation.where(client_agency_id: client_agency_id, created_at: report_range)
                       .includes(:cbv_flows, :cbv_applicant)
                       .flat_map do |invitation|
        if invitation.cbv_flows.any?
          invitation.cbv_flows.map { |flow| build_record(flow, invitation.cbv_applicant, invitation, current_agency) }
        else
          [ build_record(nil, invitation.cbv_applicant, invitation, current_agency) ]
        end
      end
    when "flows"
      CbvFlow.where(client_agency_id: client_agency_id, created_at: report_range)
             .completed
             .includes(:cbv_applicant, :cbv_flow_invitation)
             .map do |flow|
        build_record(flow, flow.cbv_applicant, flow.cbv_flow_invitation, current_agency)
      end
    else
      raise "Unknown report variant: #{report_variant}"
    end
  end

  def build_record(flow, applicant, invitation, agency)
    base_fields = {
      started_at: flow&.created_at,
      transmitted_at: flow&.transmitted_at,
      completed_at: flow&.consented_to_authorized_use_at
    }

    # Add case_number if the agency has it as an applicant attribute
    base_fields[:case_number] = applicant.case_number if agency.applicant_attributes.key?("case_number")

    if agency.include_invitation_details_on_weekly_report
      base_fields[:email_address] = invitation&.email_address
      base_fields[:invited_at] = invitation&.created_at
    end

    base_fields
  end

  def generate_csv(rows)
    return unless rows.any?

    CSV.generate(headers: rows.first.keys) do |csv|
      csv << rows.first.keys
      rows.each { |row| csv << row.values }
    end
  end
end
