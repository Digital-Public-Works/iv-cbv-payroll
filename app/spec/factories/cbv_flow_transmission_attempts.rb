FactoryBot.define do
  factory :cbv_flow_transmission_attempt do
    association :cbv_flow_transmission
    method_type { :shared_email }
    status { :pending }
    configuration { {} }
    attempt_count { 0 }
  end
end
