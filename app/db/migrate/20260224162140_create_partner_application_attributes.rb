class CreatePartnerApplicationAttributes < ActiveRecord::Migration[7.2]
  def change
    create_table :partner_application_attributes do |t|
      t.references :partner_config, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.boolean :required, null: false, default: true
      t.integer :data_type, null: false

      t.timestamps
    end
  end
end
