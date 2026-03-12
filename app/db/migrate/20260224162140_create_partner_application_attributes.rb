class CreatePartnerApplicationAttributes < ActiveRecord::Migration[7.2]
  def change
    create_table :partner_application_attributes do |t|
      t.references :partner_config, null: false, foreign_key: true
      t.string :partner_id, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :required
      t.integer :data_type

      t.timestamps
    end
  end
end
