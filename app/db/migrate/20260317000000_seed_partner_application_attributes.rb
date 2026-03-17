class SeedPartnerApplicationAttributes < ActiveRecord::Migration[7.2]
  def up
    attributes = [
      { name: "first_name", description: "Applicant first name", required: true, data_type: 0 },
      { name: "middle_name", description: "Applicant middle name", required: false, data_type: 0 },
      { name: "last_name", description: "Applicant last name", required: true, data_type: 0 },
      { name: "date_of_birth", description: "Applicant date of birth", required: true, data_type: 0 },
      { name: "case_number", description: "Case Number", required: true, data_type: 0 }
    ]

    PartnerConfig.find_each do |partner_config|
      attributes.each do |attr|
        unless PartnerApplicationAttribute.exists?(partner_config: partner_config, name: attr[:name])
          PartnerApplicationAttribute.create!(
            partner_config: partner_config,
            **attr
          )
        end
      end
    end
  end

  def down
    PartnerApplicationAttribute.delete_all
  end
end
