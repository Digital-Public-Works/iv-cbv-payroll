class AddAutoCreatedToCbvFlowInvitations < ActiveRecord::Migration[8.1]
  def change
    # Marks an invitation that the applicant's own visit to the generic link
    # created, rather than one a caseworker or partner API call created.
    add_column :cbv_flow_invitations, :auto_created, :boolean, default: false, null: false
  end
end
