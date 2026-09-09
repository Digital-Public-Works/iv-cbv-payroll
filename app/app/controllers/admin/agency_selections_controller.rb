class Admin::AgencySelectionsController < Admin::BaseController
  def create
    if agency_config.client_agency_ids.include?(params[:client_agency_id])
      session[:admin_client_agency_id] = params[:client_agency_id]
    end

    redirect_back fallback_location: admin_root_path
  end
end
