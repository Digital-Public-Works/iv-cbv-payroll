# spec/factories/partner_configs.rb
FactoryBot.define do
  factory :partner_config do
    partner_id { "sandbox" }
    name { "bbbbCBV Test Agency" }
    active_demo { true }
    active_prod { true }
    website { "https://www.example.com/contact" }
    timezone { "America/New_York" }
    domain { "sandbox" }
    argyle_environment { "sandbox" }
    logo_path { "" }
    generic_links_enabled { false }
    invitation_links_enabled { true }
    transmission_method { "shared_email" }
    pilot_ended { false }
    pay_income_days_w2 { 90 }
    pay_income_days_gig { 90 }
    staff_portal_enabled { true }
    weekly_report_enabled { true }
    weekly_report_recipients { "andre@digitalpublicworks.org,jeff@digitalpublicworks.org" }
    weekly_report_variant { "invitations" }
    invitation_valid_days_default { 14 }
    report_customization_show_earnings_list { true }

    trait :az_des do
      partner_id { "az_des" }
      name { "Department of Economic Security/Family Assistance Administration" }
      website { "https://myfamilybenefits.azdes.gov/" }
      timezone { "America/Phoenix" }
      domain { "az" }
      logo_path { "des_logo.png" }
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
      transmission_method { "sftp" }
      staff_portal_enabled { false }
    end
  end
end
