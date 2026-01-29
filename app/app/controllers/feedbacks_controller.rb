class FeedbacksController < ApplicationController
  include ApplicationHelper

  def show
    @cbv_flow = session[:cbv_flow_id] ? CbvFlow.find_by(id: session[:cbv_flow_id]) : nil
    event_name = params[:form] == "survey" ? "ApplicantClickedFeedbackSurveyLink" : "ApplicantClickedFeedbackLink"
    attributes = {
      referer: params[:referer],
      cbv_flow_id: @cbv_flow&.id,
      device_id: @cbv_flow&.device_id,
      cbv_applicant_id: @cbv_flow&.cbv_applicant_id,
      client_agency_id: @cbv_flow&.client_agency_id
    }

    event_logger.track(event_name, request, {
      time: Time.now.to_i,
      **attributes
    })

    redirect_to redirect_path, allow_other_host: true
  end

  private

  def redirect_path
    if params[:form] == "survey"
      survey_form_url + prefill_params
    else
      feedback_form_url + prefill_params
    end
  end

  def prefill_params
    language_question_field = "entry.736878711"
    en_state_question_field = "entry.1220791014"
    es_state_question_field = "entry.1932580257"

    additional_params = {
        usp: "pp_url",
        language_question_field => language_value,
        I18n.locale == :es ? es_state_question_field : en_state_question_field => state_value
      }

    query_string = additional_params.map { |k, v| "#{k}=#{ERB::Util.url_encode(v)}" }
                                    .join("&")

    "?" + query_string
  end

  def language_value
    case I18n.locale
    when :en then "English"
    when :es then "Español"
    else nil
    end
  end

  def state_value
    case @cbv_flow&.client_agency_id
    when "az_des" then "Arizona"
    when "pa_dhs" then "Pennsylvania"
    else nil
    end
  end
end
