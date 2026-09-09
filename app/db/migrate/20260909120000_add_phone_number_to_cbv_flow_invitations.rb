class AddPhoneNumberToCbvFlowInvitations < ActiveRecord::Migration[7.2]
  def change
    add_column :cbv_flow_invitations, :phone_number, :string
  end
end
