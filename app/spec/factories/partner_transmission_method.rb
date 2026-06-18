# spec/factories/partner_transmission_methods.rb
FactoryBot.define do
  factory :partner_transmission_method do
    association :partner_config
    method_type { :sftp }

    trait :shared_email do
      method_type { :shared_email }
    end

    trait :encrypted_s3 do
      method_type { :encrypted_s3 }
    end

    trait :json do
      method_type { :json }
    end

    trait :webhook do
      method_type { :webhook }
    end
  end
end
