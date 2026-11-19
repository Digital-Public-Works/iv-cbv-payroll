# each tab belongs to one flow
module CbvFlowTabBinding
  extend ActiveSupport::Concern

  TAB_FLOW_HEADER = "X-CBV-Flow-Id".freeze
  TAB_FLOW_PARAM = :cbv_flow_tab_id

  private

  def tab_cbv_flow_id
    request.headers[TAB_FLOW_HEADER].presence || params[TAB_FLOW_PARAM].presence&.to_s
  end

  def tab_flow_mismatch?(cbv_flow)
    tab_id = tab_cbv_flow_id
    tab_id.present? && tab_id != cbv_flow&.id.to_s
  end

  def session_cbv_flow_for_tab
    return nil if session[:cbv_flow_id].blank?

    cbv_flow = CbvFlow.find_by(id: session[:cbv_flow_id])
    tab_flow_mismatch?(cbv_flow) ? nil : cbv_flow
  end

  def redirect_for_tab_flow_mismatch
    Rails.logger.info(
      "Refusing request from a page for CbvFlow #{tab_cbv_flow_id}: the session now holds CbvFlow #{session[:cbv_flow_id].inspect}"
    )

    switched_path = cbv_flow_session_switched_path(locale: I18n.locale)

    # redirect properly if the 'stale' event came from a frame update
    if request.accepts.include?(Mime[:turbo_stream])
      render turbo_stream: turbo_stream.action(:redirect, switched_path), status: :conflict
    else
      redirect_to switched_path
    end
  end
end
