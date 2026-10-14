class AddReportStatusToPayrollAccounts < ActiveRecord::Migration[8.1]
  # Separates two things `synchronization_status` used to conflate:
  #
  #   synchronization_status - did the sync itself finish, and did it produce the
  #                            jobs we need? Decided as soon as the sync ends.
  #   report_status          - is the resulting report useful to an eligibility
  #                            worker? Decided by UsefulReportValidator.
  #
  # Backfills from the existing status so an account already judged useful stays
  # that way: every `succeeded` account had passed the validator under the old
  # conflated meaning. A `failed` account either failed to sync or failed the
  # validator, so its report is not useful either way (PayrollAccount keeps
  # every failed sync not_useful from here on).
  def up
    add_column :payroll_accounts, :report_status, :string, default: "unknown", null: false

    say_with_time "Backfilling payroll_accounts.report_status" do
      execute("UPDATE payroll_accounts SET report_status = 'useful' WHERE synchronization_status = 'succeeded'")
      execute("UPDATE payroll_accounts SET report_status = 'not_useful' WHERE synchronization_status = 'failed'")
    end
  end

  def down
    remove_column :payroll_accounts, :report_status
  end
end
