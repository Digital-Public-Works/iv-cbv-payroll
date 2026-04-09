class AddShowOnCaseworkerReportToPartnerApplicationAttributes < ActiveRecord::Migration[7.2]
  def up
    add_column :partner_application_attributes, :show_on_caseworker_report, :boolean, null: false, default: false

    az_des = PartnerConfig.find_by(partner_id: 'az_des')
    if az_des
      az_des.partner_application_attributes.where(name: 'case_number').update_all(show_on_caseworker_report: true)
    end

    la_ldh = PartnerConfig.find_by(partner_id: 'la_ldh')
    if la_ldh
      la_ldh.partner_application_attributes.where(name: 'doc_id').update_all(show_on_caseworker_report: true)
    end
  end

  def down
    remove_column :partner_application_attributes, :show_on_caseworker_report
  end
end
