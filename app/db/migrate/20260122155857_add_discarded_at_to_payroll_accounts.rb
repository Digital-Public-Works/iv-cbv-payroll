class AddDiscardedAtToPayrollAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :payroll_accounts, :discarded_at, :datetime
    add_index :payroll_accounts, :discarded_at
  end
end
