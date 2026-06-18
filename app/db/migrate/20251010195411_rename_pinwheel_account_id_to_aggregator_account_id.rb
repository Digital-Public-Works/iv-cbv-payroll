class RenamePinwheelAccountIdToAggregatorAccountId < ActiveRecord::Migration[7.2]
  def change
    remove_column :payroll_accounts, :aggregator_account_id, :string
    rename_column :payroll_accounts, :pinwheel_account_id, :aggregator_account_id
  end
end
