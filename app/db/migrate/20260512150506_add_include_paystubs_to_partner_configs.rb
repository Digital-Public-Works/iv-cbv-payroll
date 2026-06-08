class AddIncludePaystubsToPartnerConfigs < ActiveRecord::Migration[7.2]
  def change
    add_column :partner_configs, :include_paystubs, :boolean, default: false, null: false
  end
end
