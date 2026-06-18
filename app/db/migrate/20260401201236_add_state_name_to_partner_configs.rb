class AddStateNameToPartnerConfigs < ActiveRecord::Migration[7.2]
  def up
    add_column :partner_configs, :state_name, :string

    PartnerConfig.where(partner_id: "az_des").update_all(state_name: "Arizona")
    PartnerConfig.where(partner_id: "pa_dhs").update_all(state_name: "Pennsylvania")
  end

  def down
    remove_column :partner_configs, :state_name
  end
end
