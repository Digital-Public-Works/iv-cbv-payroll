class AddSandboxCaseworkerFieldsToPartnerApplicationAttributes < ActiveRecord::Migration[7.2]
  def up
    PartnerApplicationAttribute.reset_column_information
    sandbox = PartnerConfig.find_by(partner_id: "sandbox")
    return unless sandbox

    [
      { name: "beacon_id", description: "Your WELID", required: false, data_type: :string, form_field_type: "text_field", show_on_applicant_form: false, show_on_caseworker_form: true },
      { name: "agency_id_number", description: "Client's agency ID number", required: false, data_type: :string, form_field_type: "text_field", show_on_applicant_form: false, show_on_caseworker_form: true },
      { name: "client_id_number", description: "CIN", required: false, data_type: :string, form_field_type: "text_field", show_on_applicant_form: false, show_on_caseworker_form: true },
      { name: "snap_application_date", description: "SNAP application or recertification interview date", required: false, data_type: :date, form_field_type: "date_picker", show_on_applicant_form: false, show_on_caseworker_form: true }
    ].each do |attrs|
      sandbox.partner_application_attributes.find_or_create_by(name: attrs[:name]) do |paa|
        paa.assign_attributes(attrs)
      end
    end

    sandbox.partner_application_attributes
      .where(name: "date_of_birth")
      .update_all(show_on_caseworker_form: false)
  end

  def down
    sandbox = PartnerConfig.find_by(partner_id: "sandbox")
    return unless sandbox

    sandbox.partner_application_attributes
      .where(name: %w[beacon_id agency_id_number client_id_number snap_application_date])
      .destroy_all
  end
end
