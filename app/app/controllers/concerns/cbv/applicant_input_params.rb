# shared control for parsing out applicant-provided values
module Cbv::ApplicantInputParams
  extend ActiveSupport::Concern

  private

  def applicant_params
    permitted = @cbv_applicant.applicant_attributes.map { |attr|
      attr == :date_of_birth ? { date_of_birth: [ :day, :month, :year ] } : attr
    }

    parsed = params.fetch(applicant_param_scope, {}).permit(cbv_applicant: permitted)

    # blank is nil for validation reasons.
    cbv_attrs = parsed[:cbv_applicant]
    if cbv_attrs.is_a?(ActionController::Parameters)
      cbv_attrs.each do |key, val|
        cbv_attrs[key] = nil if val.is_a?(String) && val.empty?
      end
    end

    parsed
  end

  def applicant_param_scope
    @cbv_applicant.model_name.param_key
  end
end
