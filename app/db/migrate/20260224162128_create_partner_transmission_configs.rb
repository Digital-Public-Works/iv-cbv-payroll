class CreatePartnerTransmissionConfigs < ActiveRecord::Migration[7.2]
  def change
    create_table :partner_transmission_configs do |t|
      t.references :partner_config
      t.string :partner_id
      t.string :key
      t.text :value

      t.timestamps
    end
  end
end
