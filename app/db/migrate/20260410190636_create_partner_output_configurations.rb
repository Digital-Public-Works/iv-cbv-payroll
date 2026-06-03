class CreatePartnerOutputConfigurations < ActiveRecord::Migration[7.2]
  def change
    create_table :partner_output_configurations do |t|
      t.references :partner_config, null: false, foreign_key: true
      t.boolean :include_direct_deposit_last_4, null: false, default: false
      t.boolean :include_full_ssn, null: false, default: false

      t.timestamps
    end
  end
end
