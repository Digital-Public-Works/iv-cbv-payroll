class RenameAgencyPartnerMetadataToCustomAttributes < ActiveRecord::Migration[7.2]
  def change
    rename_column :cbv_applicants, :agency_partner_metadata, :custom_attributes
  end
end
