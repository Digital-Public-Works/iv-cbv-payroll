class CreateCbvFlowTransmissions < ActiveRecord::Migration[7.2]
  def change
    create_table :cbv_flow_transmissions do |t|
      t.references :cbv_flow, null: false, foreign_key: true
      t.integer :method_type, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :configuration, null: false, default: {}
      t.datetime :succeeded_at
      t.text :last_error
      t.timestamps
    end

    add_index :cbv_flow_transmissions,
      [ :cbv_flow_id, :method_type ],
      unique: true,
      name: "idx_cbv_flow_transmissions_on_flow_and_method"
  end
end
