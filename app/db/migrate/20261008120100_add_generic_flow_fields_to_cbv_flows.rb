class AddGenericFlowFieldsToCbvFlows < ActiveRecord::Migration[8.1]
  def change
    # Set when the flow was started by clicking a generic link (as opposed to
    # following an invitation link sent to a specific applicant).
    add_column :cbv_flows, :generic, :boolean, default: false, null: false
  end
end
