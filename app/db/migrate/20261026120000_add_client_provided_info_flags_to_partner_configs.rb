class AddClientProvidedInfoFlagsToPartnerConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :partner_configs, :allow_user_comment, :boolean, default: true, null: false
    add_column :partner_configs, :allow_outside_jobs, :boolean, default: true, null: false
  end
end
