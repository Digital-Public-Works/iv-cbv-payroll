# landing page - only is shown to applicant when they are coming from a generic link /start page
# and the partner has landing page attributes configured.
class Cbv::LandingPagesController < Cbv::BaseController
  include ApplicationHelper
  include Cbv::ApplicantInputParams

  CONTEXT = PartnerAttributeUsage::LANDING_PAGE

  before_action :set_cbv_applicant
  before_action :skip_when_nothing_to_collect, only: :show

  helper_method :applicant_field_names

  def show
    track_accessed_event
  end

  def update
    submitted = applicant_params[:cbv_applicant]
    submitted_names = submitted.present? ? submitted.to_h.keys.map(&:to_s) : []
    @cbv_applicant.assign_attributes(submitted) if submitted.present?

    if @cbv_applicant.validate_user_input(CONTEXT, submitted_names: submitted_names) && @cbv_applicant.save
      track_submitted_event
      return complete_step_and_advance
    end

    flash.now[:alert_heading] = t(".error_header", count: @cbv_applicant.errors.count)
    flash.now[:alert] = "<ul>#{@cbv_applicant.errors.map { |e| "<li>#{e.message}</li>" }.join}</ul>".html_safe

    render :show, status: :unprocessable_content
  end

  private

  def set_cbv_applicant
    @cbv_applicant = @cbv_flow.cbv_applicant
  end

  # Get applicant-provided landing page names
  def applicant_field_names
    current_agency.attribute_names_for(CONTEXT)
  end

  # skip if there are no configured landing page attributes.
  def skip_when_nothing_to_collect
    return if applicant_field_names.any?

    complete_step_and_advance
  end

  def complete_step_and_advance
    @cbv_flow.complete_landing_page_step!
    redirect_to next_path
  end

  def track_accessed_event
    event_logger.track(TrackEvent::ApplicantAccessedLandingPage, request, {
      time: Time.now.to_i,
      cbv_applicant_id: @cbv_flow.cbv_applicant_id,
      cbv_flow_id: @cbv_flow.id,
      client_agency_id: current_agency&.id,
      device_id: @cbv_flow.device_id,
      invitation_id: @cbv_flow.cbv_flow_invitation_id
    })
  end

  def track_submitted_event
    event_logger.track(TrackEvent::ApplicantSubmittedLandingPage, request, {
      time: Time.now.to_i,
      cbv_applicant_id: @cbv_flow.cbv_applicant_id,
      cbv_flow_id: @cbv_flow.id,
      client_agency_id: current_agency&.id,
      device_id: @cbv_flow.device_id,
      invitation_id: @cbv_flow.cbv_flow_invitation_id
    })
  end
end
