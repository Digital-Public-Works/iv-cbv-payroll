class AddAcronymAndPortalFlagsToPartnerConfigs < ActiveRecord::Migration[7.2]
  def change
    # Default true so existing partners keep their acronym; partners without one
    # (e.g. Mirza, RealAMI) override to false.
    add_column :partner_configs, :has_acronym, :boolean, default: true, null: false
  end
end
