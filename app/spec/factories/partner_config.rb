# spec/factories/partner_configs.rb
FactoryBot.define do
  factory :partner_config do
    partner_id { "sandbox" }
    name { "CBV Test Agency" }
    active_demo { true }
    active_prod { true }
    website { "https://www.example.com/contact" }
    timezone { "America/New_York" }
    domain { "sandbox" }
    argyle_environment { "sandbox" }
    logo_path { "" }
    generic_links_enabled { true }
    invitation_links_enabled { true }
    pilot_ended { false }
    pay_income_days_w2 { 90 }
    pay_income_days_gig { 90 }
    staff_portal_enabled { true }
    weekly_report_enabled { true }
    weekly_report_recipients { "andre@digitalpublicworks.org,jeff@digitalpublicworks.org" }
    weekly_report_variant { "invitations" }
    invitation_valid_days_default { 14 }
    report_customization_show_earnings_list { true }

    after(:create) do |partner_config, evaluator|
      if partner_config.partner_transmission_methods.empty?
        partner_config.partner_transmission_methods.create!(method_type: :shared_email)
      end
    end

    trait :az_des do
      partner_id { "az_des" }
      name { "Department of Economic Security/Family Assistance Administration" }
      website { "https://myfamilybenefits.azdes.gov/" }
      timezone { "America/Phoenix" }
      domain { "az" }
      logo_path { "des_logo.png" }
      state_name { "Arizona" }
    end

    trait :la_ldh do
      partner_id { "la_ldh" }
      name { "Department of Health" }
      website { "https://ldh.la.gov/renew-medicaid" }
      timezone { "America/Chicago" }
      domain { "la" }
      logo_path { "ldh_logo.svg" }
      generic_links_enabled { true }
      staff_portal_enabled { false }
      weekly_report_variant { "flows" }
      default_origin { "sms" }
    end

    trait :pa_dhs do
      partner_id { "pa_dhs" }
      name { "Department of Human Services" }
      website { "https://www.compass.dhs.pa.gov/home/" }
      timezone { "America/New_York" }
      domain { "pa" }
      logo_path { "pa_compass_logo.svg" }
      staff_portal_enabled { false }
      state_name { "Pennsylvania" }

      after(:create) do |partner_config|
        partner_config.partner_transmission_methods.destroy_all
        partner_config.partner_transmission_methods.create!(method_type: :sftp)
      end
    end
  end
end
