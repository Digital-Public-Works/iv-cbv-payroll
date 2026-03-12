# spec/factories/partner_application_attributes.rb
FactoryBot.define do
  factory :partner_application_attribute do
    association :partner_config, factory: :partner_config

    add_attribute(:name) { "first_name" }
    description { "Applicant first name" }
    required { true }
    data_type { "string" }

    trait :middle_name do
      add_attribute(:name) { "middle_name" }
      description { "Applicant middle name" }
      required { false }
    end

    trait :last_name do
      add_attribute(:name) { "last_name" }
      description { "Applicant last name" }
    end

    trait :date_of_birth do
      add_attribute(:name) { "date_of_birth" }
      description { "Applicant date of birth" }
      required { true }
      data_type { "string" }
    end

    trait :case_number do
      add_attribute(:name) { "case_number" }
      description { "Case Number" }
      required { true }
    end
  end
end
