FactoryBot.define do
  factory :cbv_flow_transmission do
    association :cbv_flow
    status { :pending }
  end
end
