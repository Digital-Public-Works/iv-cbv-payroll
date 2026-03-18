class SeedPartnerApplicationAttributes < ActiveRecord::Migration[7.2]
  def up
    sandbox = PartnerConfig.find_by(partner_id: "sandbox")
    return unless sandbox

    PartnerApplicationAttribute.create!(partner_config: sandbox, name: "first_name", description: "Applicant first name", required: true, data_type: 0)
    PartnerApplicationAttribute.create!(partner_config: sandbox, name: "middle_name", description: "Applicant middle name", required: false, data_type: 0)
    PartnerApplicationAttribute.create!(partner_config: sandbox, name: "last_name", description: "Applicant last name", required: true, data_type: 0)
    PartnerApplicationAttribute.create!(partner_config: sandbox, name: "date_of_birth", description: "Applicant date of birth", required: true, data_type: 0)
    PartnerApplicationAttribute.create!(partner_config: sandbox, name: "case_number", description: "Case Number", required: true, data_type: 0)
  end

  def down
    sandbox = PartnerConfig.find_by(partner_id: "sandbox")
    PartnerApplicationAttribute.where(partner_config: sandbox).delete_all if sandbox
  end
end
