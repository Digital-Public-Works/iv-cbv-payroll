class CreatePartnerTranslations < ActiveRecord::Migration[7.2]
  def change
    create_table :partner_translations do |t|
      t.references :partner_config, null: false, foreign_key: true
      t.string :locale
      t.string :key
      t.text :value

      t.timestamps
    end
  end
end
