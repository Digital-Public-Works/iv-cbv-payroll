class CreatePartnerTransmissionConfigs < ActiveRecord::Migration[7.2]
  def change
    create_table :partner_transmission_configs do |t|
      t.references :partner_config, null: false, foreign_key: true
      t.string :partner_id, null: false
      t.string :key, null: false
      t.text :value

      t.timestamps
    end
  end
end
