class Cbv::OtherJobsController < Cbv::BaseController
  before_action :skip_unless_outside_jobs_allowed

  def show
  end

  def update
    if other_jobs_params[:has_other_jobs].blank?
      flash[:slim_alert] = { message: t("shared.next_path.notice_no_answer"), type: "error", field: "has_other_jobs" }
      return redirect_to cbv_flow_other_job_path
    end

    @cbv_flow.update!(other_jobs_params)

    event_logger.track(TrackEvent::ApplicantContinuedFromOtherJobsPage, request, {
      time: Time.now.to_i,
      cbv_flow_id: @cbv_flow&.id,
      client_agency_id: @cbv_flow&.client_agency_id,
      cbv_applicant_id: @cbv_flow.cbv_applicant_id,
      device_id: @cbv_flow.device_id,
      has_other_jobs: @cbv_flow.has_other_jobs
    })
    redirect_to next_path
  end

  def next_path
    params[:cbv_flow][:return_to_path].present? ? params[:cbv_flow][:return_to_path] : super
  end

  private

  # Partners that don't ask about outside jobs skip this step, including when
  # it is reached by a direct link.
  def skip_unless_outside_jobs_allowed
    redirect_to cbv_flow_applicant_information_path unless helpers.allow_outside_jobs?
  end

  def other_jobs_params
    params.fetch(:cbv_flow, {}).permit(:has_other_jobs)
  end
end
