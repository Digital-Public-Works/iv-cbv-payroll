class CreatePartnerConfigs < ActiveRecord::Migration[7.2]
  def change
    create_table :partner_configs do |t|
      t.string :partner_id, null: false
      t.boolean :active_demo, null: false, default: false
      t.boolean :active_prod, null: false, default: false
      t.string :timezone
      t.string :name
      t.string :website
      t.string :domain
      t.string :logo_path
      t.string :argyle_environment
      t.integer :transmission_method
      t.boolean :staff_portal_enabled
      t.boolean :pilot_ended
      t.string :default_origin
      t.boolean :generic_links_enabled
      t.boolean :invitation_links_enabled
      t.integer :pay_income_days_w2
      t.integer :pay_income_days_gig
      t.integer :invitation_valid_days_default
      t.boolean :weekly_report_enabled
      t.text :weekly_report_recipients
      t.string :weekly_report_variant
      t.boolean :report_customization_show_earnings_list

      t.timestamps

      t.index :partner_id, unique: true
    end
  end
end
