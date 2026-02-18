FactoryBot.define do
  factory :cbv_flow_invitation, class: "CbvFlowInvitation" do
    client_agency_id { "sandbox" }
    email_address { "test@example.com" }
    language { :en }
    user

    cbv_applicant

    trait :sandbox do
      client_agency_id { "sandbox" }

      cbv_applicant { create(:cbv_applicant, :sandbox) }
    end

    trait :az_des do
      client_agency_id { "az_des" }

      cbv_applicant { create(:cbv_applicant, :az_des) }
    end

    trait :pa_dhs do
      client_agency_id { "pa_dhs" }

      cbv_applicant { create(:cbv_applicant, :pa_dhs) }
    end

    trait :la_ldh do
      client_agency_id { "la_ldh" }

      cbv_applicant { create(:cbv_applicant, :la_ldh) }
    end

    transient do
      cbv_applicant_attributes { {} }
      days_to_expire { 14 }
      time_zone { "UTC" }
    end

    after(:build) do |cbv_flow_invitation, evaluator|
      if cbv_flow_invitation.cbv_applicant
        cbv_flow_invitation.cbv_applicant.update(evaluator.cbv_applicant_attributes)
      end
    end

    after(:create) do |invitation, evaluator|
      if invitation.cbv_applicant
        invitation.update(expires_at: invitation.created_at.in_time_zone(evaluator.time_zone).end_of_day + 14.days)
      end

      invitation.update(expires_at: invitation.created_at.in_time_zone(evaluator.time_zone).end_of_day + evaluator.days_to_expire.days)
    end
  end
end
