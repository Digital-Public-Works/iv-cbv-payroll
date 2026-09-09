class CreateInvitationCommunications < ActiveRecord::Migration[7.2]
  def change
    create_table :invitation_communications do |t|
      t.references :cbv_flow_invitation, null: false, foreign_key: true
      t.string :channel, null: false
      t.string :status, null: false, default: "created"
      t.string :twilio_message_sid
      t.text :last_error
      t.datetime :sent_at
      t.datetime :delivered_at

      t.timestamps
    end

    add_index :invitation_communications, :twilio_message_sid, unique: true, where: "twilio_message_sid IS NOT NULL"
  end
end
