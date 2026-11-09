class AddEncourageLinkSharingToPartnerConfigs < ActiveRecord::Migration[7.2]
  def change
    add_column :partner_configs, :encourage_link_sharing, :boolean, default: true, null: false
  end
end
