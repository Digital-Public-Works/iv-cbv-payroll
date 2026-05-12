class CreatePartnerTransmissionMethods < ActiveRecord::Migration[7.2]
  def up
    create_table :partner_transmission_methods do |t|
      t.references :partner_config, null: false, foreign_key: true
      t.integer :method_type, null: false
      t.timestamps
    end

    add_reference :partner_transmission_configs, :partner_transmission_method,
      null: true, foreign_key: true

    # Migrate existing data: create a PartnerTransmissionMethod for each
    # PartnerConfig that has a transmission_method set, then associate its
    # PartnerTransmissionConfigs with the new record.
    execute <<~SQL
      INSERT INTO partner_transmission_methods (partner_config_id, method_type, created_at, updated_at)
      SELECT id, transmission_method, NOW(), NOW()
      FROM partner_configs
      WHERE transmission_method IS NOT NULL
    SQL

    execute <<~SQL
      UPDATE partner_transmission_configs
      SET partner_transmission_method_id = ptm.id
      FROM partner_transmission_methods ptm
      WHERE partner_transmission_configs.partner_config_id = ptm.partner_config_id
    SQL

    change_column_null :partner_transmission_configs, :partner_transmission_method_id, false

    remove_reference :partner_transmission_configs, :partner_config, foreign_key: true

    remove_column :partner_configs, :transmission_method
  end

  def down
    add_column :partner_configs, :transmission_method, :integer

    # Restore transmission_method on partner_configs from first transmission method
    execute <<~SQL
      UPDATE partner_configs
      SET transmission_method = ptm.method_type
      FROM (
        SELECT DISTINCT ON (partner_config_id) partner_config_id, method_type
        FROM partner_transmission_methods
        ORDER BY partner_config_id, id
      ) ptm
      WHERE partner_configs.id = ptm.partner_config_id
    SQL

    # Restore partner_config_id on partner_transmission_configs
    add_reference :partner_transmission_configs, :partner_config, null: true, foreign_key: true

    execute <<~SQL
      UPDATE partner_transmission_configs
      SET partner_config_id = ptm.partner_config_id
      FROM partner_transmission_methods ptm
      WHERE partner_transmission_configs.partner_transmission_method_id = ptm.id
    SQL

    change_column_null :partner_transmission_configs, :partner_config_id, false
    remove_reference :partner_transmission_configs, :partner_transmission_method
    drop_table :partner_transmission_methods
  end
end
