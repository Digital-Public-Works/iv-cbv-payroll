class CreatePartnerTransmissionConfigs < ActiveRecord::Migration[7.2]
  def change
    create_table :partner_transmission_configs do |t|
      t.references :partner_config, null: false, foreign_key: true
      t.string :key, null: false
      t.text :value
      t.boolean :is_encrypted, null: false, default: false

      t.timestamps
    end
  end
end
