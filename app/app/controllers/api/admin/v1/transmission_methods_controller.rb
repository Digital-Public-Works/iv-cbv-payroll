class Api::Admin::V1::TransmissionMethodsController < Api::Admin::V1::BaseController
  before_action :find_partner

  # Replaces the partner's transmission methods. If $ENCRYPTED is passed in for a secret, the value in the db is not changed
  def update
    methods = body_json["transmission_methods"]
    changed = methods.is_a?(Array) ? methods.filter_map { |m| m["method_type"] if m.is_a?(Hash) } : []
    logged("replace_transmission_methods", partner_id: @partner.partner_id, changed: changed) do
      AdminApi::PartnerWrites.new.replace_transmission_methods(@partner, methods, expected_version: body_json["updated_at"])
      render_detail(@partner)
    end
  end

  def check
    method = @partner.partner_transmission_methods.find { |m| m.method_type == params[:method_type] }
    return render(json: { message: "No #{params[:method_type]} method for '#{@partner.partner_id}'" }, status: :not_found) unless method

    result = AdminApi::ConnectivityCheck.call(method)
    AdminApi::ActionLog.record(action: "connectivity_check", actor: current_actor, partner_id: @partner.partner_id,
                               changed: [ method.method_type ], result: result[:ok] ? "ok" : "failed")
    render json: result
  end
end
