class Api::InvitationsController < ApplicationController
  skip_forgery_protection
  wrap_parameters false

  before_action :authenticate

  def create
    missing = missing_required_metadata_keys
    if missing.any?
      return render json: missing_required_errors(missing), status: :bad_request
    end

    cbv_flow_invitation = CbvInvitationService.new(event_logger)
      .invite(cbv_flow_invitation_params, @current_user, delivery_method: nil)

    errors = cbv_flow_invitation.errors
    if errors.any?
      e = errors.full_messages.join(", ")
      Rails.logger.warn("Error inviting applicant: #{e}")
      return render json: errors_to_json(errors), status: :unprocessable_entity
    end

    render json: {
      tokenized_url: cbv_flow_invitation.to_url,
      expiration_date: cbv_flow_invitation.expires_at_local,
      language: cbv_flow_invitation.language
    }, status: :created
  end

  private

  def partner_config
    @partner_config ||= ClientAgencyConfig.instance[@current_user.client_agency_id]
  end

  def cbv_flow_invitation_params
    client_agency_id = @current_user.client_agency_id

    # Top-level invitation params (language, email, expiration).
    permitted = params.without(:client_agency_id, :agency_partner_metadata).permit(
      :language, :email_address, :user_id, :expiration_date, :expiration_days
    )

    # Split the incoming agency_partner_metadata hash by destination on
    # cbv_applicants:
    #   - The key matching `partner_identifier_name` → partner_identifier column.
    #   - Keys that match real columns (date_of_birth, snap_application_date, etc.)
    #     → assigned directly to those columns.
    #   - Everything else → packed into the agency_partner_metadata jsonb.
    incoming = unsafe_metadata_hash
    identifier_name = partner_config.partner_identifier_name
    real_columns = CbvApplicant.column_names

    partner_identifier_value = nil
    metadata = {}
    direct_column_assignments = {}

    partner_config.applicant_attributes.keys.each do |name|
      key = name.to_s
      value = incoming[name]
      if identifier_name.present? && key == identifier_name.to_s
        partner_identifier_value = value
      elsif real_columns.include?(key)
        direct_column_assignments[key.to_sym] = value
      else
        metadata[key] = value
      end
    end

    cbv_applicant_attrs = {
      client_agency_id: client_agency_id,
      partner_identifier: partner_identifier_value,
      agency_partner_metadata: metadata
    }.merge(direct_column_assignments)

    permitted.deep_merge!(
      client_agency_id: client_agency_id,
      email_address: @current_user.email,
      cbv_applicant_attributes: cbv_applicant_attrs
    )
  end

  def missing_required_metadata_keys
    incoming = unsafe_metadata_hash
    required_attrs = partner_config.applicant_attributes.select { |_name, attr| attr.required }
    required_attrs.keys.reject { |name| incoming[name].present? }
  end

  # create output matching the expected data, drop anything unexpected.
  def unsafe_metadata_hash
    raw = params[:agency_partner_metadata]
    return {} if raw.blank?
    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
  end

  def missing_required_errors(missing)
    {
      errors: missing.map do |name|
        { field: "agency_partner_metadata.#{name}", message: "is required" }
      end
    }
  end

  def authenticate
    authenticate_or_request_with_http_token do |token, options|
      @current_user = User.find_by_access_token(token)
    end
  end

  def errors_to_json(errors)
    # Generates a Hash of attribute => error_message and translates the
    # internal names of objects (cbv_applicant) to the external names
    # (agency_partner_metadata)
    error_messages = errors.map do |error|
      next if error.attribute == :cbv_applicant

      error_message = error.message

      case error
      when ActiveModel::NestedError
        prefix, attribute_name = error.attribute.to_s.split(".")
        prefix = "agency_partner_metadata" if prefix == "cbv_applicant"

        { field: "#{prefix}.#{attribute_name}", message: error_message }
      else
        { field: error.attribute, message: error_message }
      end
    end.compact

    { errors: error_messages }
  end
end
