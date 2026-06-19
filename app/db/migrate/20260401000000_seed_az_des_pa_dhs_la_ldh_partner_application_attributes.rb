class SeedAzDesPaDhsLaLdhPartnerApplicationAttributes < ActiveRecord::Migration[7.2]
  def up
    PartnerApplicationAttribute.reset_column_information

    seed_az_des
    seed_pa_dhs
    seed_la_ldh
  end

  def down
    %w[az_des pa_dhs la_ldh].each do |partner_id|
      config = PartnerConfig.find_by(partner_id: partner_id)
      PartnerApplicationAttribute.where(partner_config: config).delete_all if config
    end
  end

  private

  def seed_az_des
    config = PartnerConfig.find_by(partner_id: "az_des")
    return unless config

    [
      { name: "first_name", description: "Applicant first name", required: false, data_type: :string,
        redactable: true, redact_type: "string", show_on_caseworker_form: true, show_on_applicant_form: false },
      { name: "middle_name", description: "Applicant middle name", required: false, data_type: :string,
        redactable: true, redact_type: "string", show_on_caseworker_form: true, show_on_applicant_form: false },
      { name: "last_name", description: "Applicant last name", required: false, data_type: :string,
        redactable: true, redact_type: "string", show_on_caseworker_form: true, show_on_applicant_form: false },
      { name: "case_number", description: "Case number", required: true, data_type: :string,
        redactable: false, show_on_caseworker_form: true, show_on_applicant_form: false, show_on_caseworker_report: true },
      { name: "income_changes", description: "Income changes", required: false, data_type: :string,
        redactable: false, show_on_caseworker_form: false, show_on_applicant_form: false }
    ].each do |attrs|
      config.partner_application_attributes.find_or_create_by(name: attrs[:name]) do |paa|
        paa.assign_attributes(attrs)
      end
    end
  end

  def seed_pa_dhs
    config = PartnerConfig.find_by(partner_id: "pa_dhs")
    return unless config

    [
      { name: "case_number", description: "Case number", required: true, data_type: :string,
        redactable: false, show_on_caseworker_form: true, show_on_applicant_form: false }
    ].each do |attrs|
      config.partner_application_attributes.find_or_create_by(name: attrs[:name]) do |paa|
        paa.assign_attributes(attrs)
      end
    end
  end

  def seed_la_ldh
    config = PartnerConfig.find_by(partner_id: "la_ldh")
    return unless config

    [
      { name: "case_number", description: "Medicaid case number", required: false, data_type: :string,
        redactable: false, show_on_caseworker_form: false, show_on_applicant_form: true },
      { name: "date_of_birth", description: "Applicant date of birth", required: true, data_type: :date,
        form_field_type: "memorable_date", redactable: true, redact_type: "date",
        show_on_caseworker_form: false, show_on_applicant_form: true },
      { name: "doc_id", description: "Document ID", required: false, data_type: :string,
        redactable: false, show_on_caseworker_form: false, show_on_applicant_form: false, show_on_caseworker_report: true }
    ].each do |attrs|
      config.partner_application_attributes.find_or_create_by(name: attrs[:name]) do |paa|
        paa.assign_attributes(attrs)
      end
    end
  end
end
