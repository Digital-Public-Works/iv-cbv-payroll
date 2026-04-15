class CreateCbvFlowTransmissions < ActiveRecord::Migration[7.2]
  def change
    create_table :cbv_flow_transmissions do |t|
      t.references :cbv_flow, null: false, foreign_key: true, index: { unique: true }
      t.integer :status, null: false, default: 0
      t.datetime :completed_at
      t.timestamps
    end

    create_table :cbv_flow_transmission_attempts do |t|
      t.references :cbv_flow_transmission, null: false, foreign_key: true
      t.integer :method_type, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :configuration, null: false, default: {}
      t.integer :attempt_count, null: false, default: 0
      t.text :last_error
      t.datetime :last_attempted_at
      t.datetime :succeeded_at
      t.timestamps
    end

    add_index :cbv_flow_transmission_attempts,
      [ :cbv_flow_transmission_id, :method_type ],
      unique: true,
      name: "idx_cbv_flow_tx_attempts_on_tx_and_method"
  end
end
