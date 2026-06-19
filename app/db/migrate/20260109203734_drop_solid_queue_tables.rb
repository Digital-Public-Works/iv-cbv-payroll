class DropSolidQueueTables < ActiveRecord::Migration[7.2]
  def up
    # Drop FKs first (so tables can be dropped cleanly)
    remove_foreign_key :solid_queue_blocked_executions, column: :job_id rescue nil
    remove_foreign_key :solid_queue_claimed_executions, column: :job_id rescue nil
    remove_foreign_key :solid_queue_failed_executions,  column: :job_id rescue nil
    remove_foreign_key :solid_queue_ready_executions,   column: :job_id rescue nil
    remove_foreign_key :solid_queue_scheduled_executions, column: :job_id rescue nil
    remove_foreign_key :solid_queue_recurring_executions, column: :job_id rescue nil

    # Drop tables that depend on solid_queue_jobs first
    drop_table :solid_queue_failed_executions, if_exists: true
    drop_table :solid_queue_blocked_executions, if_exists: true
    drop_table :solid_queue_claimed_executions, if_exists: true
    drop_table :solid_queue_ready_executions, if_exists: true
    drop_table :solid_queue_scheduled_executions, if_exists: true
    drop_table :solid_queue_recurring_executions, if_exists: true

    # Then drop the rest
    drop_table :solid_queue_semaphores, if_exists: true
    drop_table :solid_queue_processes, if_exists: true
    drop_table :solid_queue_pauses, if_exists: true
    drop_table :solid_queue_jobs, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "SolidQueue tables were dropped"
  end
end
