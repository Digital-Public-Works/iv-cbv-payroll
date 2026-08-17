# This migration comes from solid_queue (originally 20240813160053)
# SolidQueue has been removed from the project, so this migration is a no-op.
# The original migration code is commented out below - it cannot run because
# the SolidQueue gem is no longer a dependency.
class MakeNameNotNull < ActiveRecord::Migration[7.1]
  def up
    # Original code (disabled - SolidQueue gem removed from project):
    # SolidQueue::Process.where(name: nil).find_each do |process|
    #   process.name ||= [ process.kind.downcase, SecureRandom.hex(10) ].join("-")
    #   process.save!
    # end
    #
    # change_column :solid_queue_processes, :name, :string, null: false
    # add_index :solid_queue_processes, [ :name, :supervisor_id ], unique: true
    #
    # SolidQueue tables are dropped in a later migration, so these schema
    # changes are not needed. This migration is now a no-op.
  end

  def down
    # No-op since SolidQueue is no longer in use
  end
end
