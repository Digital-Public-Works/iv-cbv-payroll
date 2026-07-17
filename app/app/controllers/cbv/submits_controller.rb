require "csv"
require "combine_pdf"
require "tempfile"
require "zlib"

class Cbv::SubmitsController < Cbv::BaseController
  include Cbv::AggregatorDataHelper
  include GpgEncryptable
  include TarFileCreatable
  include CsvHelper
  include NonProductionAccessible

  before_action :set_aggregator_report, only: %i[show update]
  before_action :check_aggregator_report, only: %i[show update]

  helper "cbv/aggregator_data"

  helper_method :has_consent
  skip_before_action :ensure_cbv_flow_not_yet_complete, if: -> { params[:format] == "pdf" }

  def show
    respond_to do |format|
      format.html
      format.pdf do
        event_logger.track(TrackEvent::ApplicantDownloadedIncomePDF, request, {
          time: Time.now.to_i,
          client_agency_id: current_agency&.id,
          cbv_applicant_id: @cbv_flow.cbv_applicant_id,
          cbv_flow_id: @cbv_flow.id,
          device_id: @cbv_flow.device_id,
          invitation_id: @cbv_flow.cbv_flow_invitation_id,
          locale: I18n.locale
        })

        send_data generate_client_pdf,
          type: "application/pdf",
          disposition: "inline",
          filename: "#{@cbv_flow.id}.pdf"
      end
    end

    track_accessed_submit_event(@cbv_flow)
  end

  def update
    unless has_consent
      @cbv_flow.errors.add(:consent_to_authorized_use, :blank, message: t(".consent_to_authorize_warning"))
      return redirect_to(cbv_flow_submit_path, flash: { alert: t(".consent_to_authorize_warning") })
    end

    if params[:cbv_flow] && params[:cbv_flow][:consent_to_authorized_use] == "1"
      timestamp = Time.now.to_datetime
      @cbv_flow.update(consented_to_authorized_use_at: timestamp)
    end

    if @cbv_flow.confirmation_code.blank?
      confirmation_code = generate_confirmation_code(@cbv_flow)
      @cbv_flow.update!(confirmation_code: confirmation_code)
    end

    CaseWorkerTransmitterJob.perform_later(@cbv_flow.id)
    redirect_to next_path
  end

  private

  def generate_client_pdf
    html = render_to_string(
      template: "cbv/submits/show",
      formats: [ :pdf ],
      layout: "layouts/pdf",
      locals: {
        is_caseworker: is_not_production? && params[:is_caseworker],
        aggregator_report: @aggregator_report
      }
    )

    report_pdf = WickedPdf.new.pdf_from_string(
      html,
      footer: { right: t("cbv.submits.show.pdf.footer.page_footer"), font_size: 10 },
      margin: { top: 10, bottom: 10, left: 10, right: 10 }
    )

    # If this agency is not configured to include paystubs, just return the report without the paystubs.
    # The code below this return adds the paystubs + cover page to the report.
    return report_pdf unless current_agency&.include_paystubs

    begin
      paystubs_result = Aggregators::PaystubsPdfService.new(
        cbv_flow: @cbv_flow,
        argyle_service: Aggregators::Sdk::ArgyleService.new(current_agency.argyle_environment)
      ).generate
      merge_pdfs(report_pdf, paystubs_result.content)
    rescue Aggregators::PaystubsPdfService::NoPaystubsError => e
      Rails.logger.warn "Client PDF download: no paystub documents found; omitting paystubs section: #{e.message}"
      report_pdf
    end
  end

  def merge_pdfs(pdf1_bytes, pdf2_bytes)
    return pdf2_bytes if pdf1_bytes.blank?
    return pdf1_bytes if pdf2_bytes.blank?

    target = CombinePDF.new
    [ pdf1_bytes, pdf2_bytes ].each { |bytes| target << CombinePDF.parse(bytes) }
    target.to_pdf
  end

  def check_aggregator_report
    if @aggregator_report.nil?
      Rails.logger.error "Aggregator report nil for #{@cbv_flow.id}. Investigate, as we didn't think it should be possible to get here because at least one account should be usable."
      redirect_to cbv_flow_synchronization_failures_path
    end
  end

  def has_consent
    return true if @cbv_flow.consented_to_authorized_use_at.present?
    params[:cbv_flow] && params[:cbv_flow][:consent_to_authorized_use] == "1"
  end

  def track_accessed_submit_event(cbv_flow)
    event_logger.track(TrackEvent::ApplicantAccessedSubmitPage, request, {
      time: Time.now.to_i,
      client_agency_id: current_agency&.id,
      cbv_flow_id: cbv_flow.id,
      cbv_applicant_id: cbv_flow.cbv_applicant_id,
      device_id: @cbv_flow.device_id,
      invitation_id: cbv_flow.cbv_flow_invitation_id,
      flow_started_seconds_ago: (Time.now - cbv_flow.created_at).to_i,
      locale: I18n.locale
    })
  end

  def generate_confirmation_code(cbv_flow)
    prefix = cbv_flow.client_agency_id
    [
      prefix.gsub("_", ""),
      (Time.now.to_i % 36 ** 3).to_s(36).tr("OISB", "0158").rjust(3, "0"),
      cbv_flow.id.to_s.rjust(4, "0")
    ].compact.join.upcase
  end
end
