class DropGlobalRequiredFromPartnerApplicationAttributes < ActiveRecord::Migration[8.1]
  # Both columns are now expressed per-context in partner_attribute_usages,
  # which CreatePartnerAttributeUsages backfilled from them.
  def change
    remove_column :partner_application_attributes, :required, :boolean, default: true, null: false
    remove_column :partner_application_attributes, :show_on_applicant_form, :boolean, default: true, null: false
  end
end
