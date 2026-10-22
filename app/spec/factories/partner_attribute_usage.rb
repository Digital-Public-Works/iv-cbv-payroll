FactoryBot.define do
  factory :partner_attribute_usage do
    association :partner_config, factory: :partner_config
    add_attribute(:context) { PartnerAttributeUsage::APPLICANT_INPUT_PAGE }
    add_attribute(:name) { "first_name" }
    required { true }
    position { 0 }
  end
end
