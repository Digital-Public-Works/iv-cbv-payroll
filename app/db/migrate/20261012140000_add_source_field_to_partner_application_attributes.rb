class AddSourceFieldToPartnerApplicationAttributes < ActiveRecord::Migration[8.1]
  def change
    add_column :partner_application_attributes, :source_field, :string
  end
end
