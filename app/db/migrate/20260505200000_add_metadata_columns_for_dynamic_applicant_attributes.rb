class AddMetadataColumnsForDynamicApplicantAttributes < ActiveRecord::Migration[7.2]
  def change
    add_column :cbv_applicants, :agency_partner_metadata, :jsonb, null: false, default: {}
    add_column :cbv_applicants, :partner_identifier, :string
    add_column :partner_configs, :partner_identifier_name, :string

    add_index :cbv_applicants, :partner_identifier
  end
end
