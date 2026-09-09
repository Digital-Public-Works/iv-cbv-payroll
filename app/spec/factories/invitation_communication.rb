FactoryBot.define do
  factory :invitation_communication do
    cbv_flow_invitation
    channel { :sms }
    status { :created }
  end
end
