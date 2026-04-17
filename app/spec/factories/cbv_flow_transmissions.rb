FactoryBot.define do
  factory :cbv_flow_transmission do
    association :cbv_flow
    method_type { :shared_email }
    status { :pending }
    configuration { {} }
  end
end
