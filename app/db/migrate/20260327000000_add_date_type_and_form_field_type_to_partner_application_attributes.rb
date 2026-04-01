class AddDateTypeAndFormFieldTypeToPartnerApplicationAttributes < ActiveRecord::Migration[7.2]
  def up
    add_column :partner_application_attributes, :form_field_type, :string, default: "text_field"

    PartnerApplicationAttribute.where(name: "date_of_birth").update_all(data_type: 3, form_field_type: "memorable_date")

    PartnerApplicationAttribute.where(name: "snap_application_date").update_all(data_type: 3, form_field_type: "date_picker")
  end

  def down
    PartnerApplicationAttribute.where(name: "date_of_birth").update_all(data_type: 0)
    PartnerApplicationAttribute.where(name: "snap_application_date").update_all(data_type: 0)
    remove_column :partner_application_attributes, :form_field_type
  end
end
