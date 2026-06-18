class Cbv::ValidationFailuresController < Cbv::BaseController
  include Cbv::AggregatorDataHelper
  helper_method :count_of_valid_accounts

  def show
    account_id = params[:user][:account_id]
    @payroll_account = @cbv_flow.payroll_accounts.find_by(aggregator_account_id: account_id)

    # security check - make sure the account_id is associated with the current cbv_flow_id
    if @payroll_account.nil?
      return redirect_to(cbv_flow_entry_url, flash: { slim_alert: { message: t("cbv.error_no_access"), type: "error" } })
    end

    set_aggregator_report_for_account(@payroll_account)
  end

  def count_of_valid_accounts
    @cbv_flow.accounts_with_required_data&.size || 0
  end
end
