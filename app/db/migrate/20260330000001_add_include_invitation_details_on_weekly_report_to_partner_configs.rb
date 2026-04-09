class AddIncludeInvitationDetailsOnWeeklyReportToPartnerConfigs < ActiveRecord::Migration[7.2]
  def up
    add_column :partner_configs, :include_invitation_details_on_weekly_report, :boolean, null: false, default: false

    PartnerConfig.where(partner_id: %w[az_des pa_dhs]).update_all(include_invitation_details_on_weekly_report: true)
  end

  def down
    remove_column :partner_configs, :include_invitation_details_on_weekly_report
  end
end
