class Api::UserEventsController < ApplicationController
  def user_action
    base_attributes = {
      time: Time.now.to_i
    }

    if session[:cbv_flow_id].present?
      @cbv_flow = CbvFlow.find(session[:cbv_flow_id])

      base_attributes.merge!({
        cbv_flow_id: @cbv_flow.id,
        cbv_applicant_id: @cbv_flow.cbv_applicant_id,
        client_agency_id: @cbv_flow.client_agency_id,
        device_id: @cbv_flow.device_id,
        invitation_id: @cbv_flow.cbv_flow_invitation_id
      })
    end

    event_attributes = (user_action_params[:attributes] || {}).merge(base_attributes)
    event_name = user_action_params[:event_name]

    if TrackEvent.constants.map(&:to_s).include?(event_name)
      event_logger.track(
        event_name,
        request,
        event_attributes.to_h
      )
    else
      raise "Unknown Event Type #{event_name.inspect}"
    end

    if event_name == "ApplicantRemovedArgyleAccount" && @cbv_flow.present?
      discard_argyle_payroll_account(event_attributes)
    end

    render json: { status: :ok }

  rescue => ex
    raise ex unless Rails.env.production?

    NewRelic::Agent.notice_error(ex)
    Rails.logger.error "Unable to process user action: #{ex}"
    render json: { status: :error }, status: :unprocessable_entity
  end

  private

  def user_action_params
    params.fetch(:events, {}).permit(:event_name, attributes: {})
  end

  def discard_argyle_payroll_account(event_attributes)
    account_id = event_attributes["argyle.accountId"]
    return if account_id.blank?

    payroll_account = @cbv_flow.payroll_accounts.find_by(type: :argyle, aggregator_account_id: account_id)
    payroll_account&.discard!
  rescue => ex
    NewRelic::Agent.notice_error(ex) if defined?(NewRelic::Agent)
    Rails.logger.error "Unable to discard payroll_account for ApplicantRemovedArgyleAccount: #{ex}"
  end
end
