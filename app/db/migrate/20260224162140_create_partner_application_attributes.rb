class CreatePartnerApplicationAttributes < ActiveRecord::Migration[7.2]
  def change
    create_table :partner_application_attributes do |t|
      t.references :partner_config
      t.string :partner_id
      t.string :name
      t.text :description
      t.boolean :required
      t.integer :data_type

      t.timestamps
    end
  end
end
