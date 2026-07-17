class AddOutputConfigurationToPartnerConfigs < ActiveRecord::Migration[7.2]
  def change
    add_column :partner_configs, :include_full_ssn, :boolean, null: false, default: false
    add_column :partner_configs, :include_direct_deposit_last_4, :boolean, null: false, default: false
  end
end
