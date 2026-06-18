class AddShowOnFormFlagsToPartnerApplicationAttributes < ActiveRecord::Migration[7.2]
  def change
    add_column :partner_application_attributes, :show_on_applicant_form, :boolean, null: false, default: true
    add_column :partner_application_attributes, :show_on_caseworker_form, :boolean, null: false, default: true
  end
end
