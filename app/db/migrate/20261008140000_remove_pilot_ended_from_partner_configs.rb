class RemovePilotEndedFromPartnerConfigs < ActiveRecord::Migration[8.1]
  # Retired. It blocked the same entry points as generic_links_enabled and
  # invitation_links_enabled turned off together, never stopped a flow already
  # in progress, and no longer had any wind-down copy to show. Turn both flow
  # flags off to wind a partner down.
  def change
    remove_column :partner_configs, :pilot_ended, :boolean, default: false, null: false
  end
end
