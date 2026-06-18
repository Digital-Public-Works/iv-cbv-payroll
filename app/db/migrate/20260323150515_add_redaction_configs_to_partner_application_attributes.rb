class AddRedactionConfigsToPartnerApplicationAttributes < ActiveRecord::Migration[7.2]
  def up
    add_column :partner_application_attributes, :redactable, :boolean, null: false, default: false
    add_column :partner_application_attributes, :redact_type, :string

    redactable_fields = {
      "az_des" => { first_name: :string, middle_name: :string, last_name: :string },
      "pa_dhs" => { first_name: :string, middle_name: :string, last_name: :string },
      "la_ldh" => { date_of_birth: :date },
      "sandbox" => { first_name: :string, middle_name: :string, last_name: :string, date_of_birth: :date }
    }

    redactable_fields.each do |partner_id, fields|
      partner = PartnerConfig.find_by(partner_id: partner_id)
      next unless partner

      fields.each do |field_name, type|
        partner.partner_application_attributes
          .where(name: field_name.to_s)
          .update_all(redactable: true, redact_type: type.to_s)
      end
    end
  end

  def down
    remove_column :partner_application_attributes, :redactable
    remove_column :partner_application_attributes, :redact_type
  end
end
