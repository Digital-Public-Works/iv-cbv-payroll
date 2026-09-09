class RenameTwilioMessageSidToProviderMessageId < ActiveRecord::Migration[7.2]
  def change
    rename_column :invitation_communications, :twilio_message_sid, :provider_message_id
  end
end
