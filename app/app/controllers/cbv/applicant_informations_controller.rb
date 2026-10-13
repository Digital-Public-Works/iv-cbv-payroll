class Cbv::ApplicantInformationsController < Cbv::BaseController
  include ApplicationHelper
  include Cbv::ApplicantInputParams

  before_action :set_cbv_applicant, only: %i[show update]
  before_action :skip_when_nothing_to_collect, only: :show

  helper_method :show_all_applicant_fields?, :applicant_field_names

  CONTEXT = PartnerAttributeUsage::APPLICANT_INPUT_PAGE

  def show
    track_applicant_information_access_event
  end

  def update
    submitted = applicant_params[:cbv_applicant]
    submitted_names = submitted.present? ? submitted.to_h.keys.map(&:to_s) : []
    @cbv_applicant.assign_attributes(submitted) if submitted.present?

    if @cbv_applicant.validate_user_input(CONTEXT, submitted_names: submitted_names) && @cbv_applicant.save
      track_applicant_submitted_information_page_event
      return redirect_to next_path
    end

    error_header = t(".error_header", count: @cbv_applicant.errors.count)

    # Use @cbv_applicant.errors directly since we added all errors back to it
    error_messages = @cbv_applicant.errors.map { |error| "<li>#{error.message}</li>" }.join
    error_messages = "<ul>#{error_messages}</ul>"

    flash.now[:alert_heading] = error_header
    flash.now[:alert] = error_messages.html_safe

    track_applicant_information_error_event(error_messages.html_safe)

    render :show, status: :unprocessable_content

    # note: if we TRULY want that rescue behavior, keep it here. i still think this was a legacy of the save! hack, but it can go here
  rescue Exception => e
    Rails.logger.error("Error updating applicant: #{e.message}")
    flash[:alert] = t(".error_updating_applicant")
    redirect_to cbv_flow_applicant_information_path
  end

  private

  # renders required user input that has not yet been populated
  def applicant_field_names
    if show_all_applicant_fields?
      current_agency.attribute_names_for(CONTEXT) | current_agency.required_for_submit_attributes
    else
      @cbv_applicant.fields_to_collect_for(CONTEXT)
    end
  end

  # skip this step if all required data is populated.
  def skip_when_nothing_to_collect
    return if show_all_applicant_fields?
    return if applicant_field_names.any?

    redirect_to next_path
  end

  # show all populated data if the applicant says 'edit my data'.
  def show_all_applicant_fields?
    params[:force_show] == "true" || action_name == "update"
  end

  def set_cbv_applicant
    @cbv_applicant = @cbv_flow.cbv_applicant
  end

  def track_applicant_information_access_event
    if params[:force_show] == "true"
      event_logger.track(TrackEvent::ApplicantClickedEditInformationLink, request, {
        time: Time.now.to_i,
        cbv_applicant_id: @cbv_flow.cbv_applicant_id,
        client_agency_id: current_agency&.id,
        cbv_flow_id: @cbv_flow.id,
        device_id: @cbv_flow.device_id
      })
    else
      event_logger.track(TrackEvent::ApplicantAccessedInformationPage, request, {
        time: Time.now.to_i,
        cbv_applicant_id: @cbv_flow.cbv_applicant_id,
        client_agency_id: current_agency&.id,
        cbv_flow_id: @cbv_flow.id,
        device_id: @cbv_flow.device_id
      })
    end
  end

  def track_applicant_information_error_event(error_string)
    event_logger.track(TrackEvent::ApplicantEncounteredInformationPageError, request, {
      time: Time.now.to_i,
      cbv_applicant_id: @cbv_flow.cbv_applicant_id,
      cbv_flow_id: @cbv_flow.id,
      client_agency_id: current_agency&.id,
      device_id: @cbv_flow.device_id,
      error_string: error_string
    })
  end

  def track_applicant_submitted_information_page_event
    event_logger.track(TrackEvent::ApplicantSubmittedInformationPage, request, {
      time: Time.now.to_i,
      cbv_applicant_id: @cbv_flow.cbv_applicant_id,
      cbv_flow_id: @cbv_flow.id,
      client_agency_id: current_agency&.id,
      device_id: @cbv_flow.device_id,
      invitation_id: @cbv_flow.cbv_flow_invitation_id,
      identity_age_range_applicant: get_age_range(@cbv_applicant.date_of_birth)
    })
  end
end
