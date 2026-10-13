require "rails_helper"

# Verifies the three shapes a partner can be configured in — invitation only,
# both, and generic only — by walking each entry point for a purpose-built
# partner rather than reasoning about the flags.
RSpec.describe "Partner flow configurations", type: :request do
  # Builds a partner with the usual five applicant attributes, asked for on an
  # invitation (first/last/case_number required) and, where configured, at the
  # landing page and on the applicant-information page.
  def build_partner(partner_id, generic:, invitations:, landing_page: [])
    # A subdomain has to be a valid hostname, so the slug is hyphenated even
    # though the partner_id is not.
    config = FactoryBot.create(:partner_config,
      partner_id: partner_id,
      domain: partner_id.tr("_", "-"),
      generic_links_enabled: generic,
      invitation_links_enabled: invitations)

    %i[first_name middle_name last_name date_of_birth case_number].each do |attr|
      trait = attr == :first_name ? nil : attr
      trait ? FactoryBot.create(:partner_application_attribute, trait, partner_config: config)
            : FactoryBot.create(:partner_application_attribute, partner_config: config)
    end

    required = %w[first_name last_name case_number]
    %w[first_name middle_name last_name date_of_birth case_number].each_with_index do |name, i|
      PartnerAttributeUsage.create!(partner_config: config, context: PartnerAttributeUsage::INVITATION,
                                    name: name, required: required.include?(name), position: i)
      PartnerAttributeUsage.create!(partner_config: config, context: PartnerAttributeUsage::APPLICANT_INPUT_PAGE,
                                    name: name, required: required.include?(name), position: i)
    end

    landing_page.each_with_index do |name, i|
      PartnerAttributeUsage.create!(partner_config: config, context: PartnerAttributeUsage::LANDING_PAGE,
                                    name: name, required: true, position: i)
    end

    ClientAgencyConfig.reset!
    config
  end

  def create_api_invitation(partner_id, custom_attributes:)
    user = FactoryBot.create(:user, :with_access_token,
      email: "api-#{partner_id.tr('_', '-')}@example.com", client_agency_id: partner_id, is_service_account: true)

    post "/api/v1/invitations",
      params: { language: "en", custom_attributes: custom_attributes }.to_json,
      headers: {
        "Authorization" => "Bearer #{user.api_access_tokens.first.access_token}",
        "Content-Type" => "application/json"
      }
  end

  let(:full_attributes) do
    { first_name: "Daph", last_name: "Gold", case_number: "9971" }
  end

  # Everything on the partner's applicant_input_page list, so the applicant-information
  # page has nothing left to ask about.
  let(:every_attribute) do
    full_attributes.merge(middle_name: "Q", date_of_birth: "03/19/1992")
  end

  describe "a partner that uses invitations only" do
    before { build_partner("inv_only", generic: false, invitations: true) }

    it "creates an invitation through the API" do
      create_api_invitation("inv_only", custom_attributes: full_attributes)

      expect(response).to have_http_status(:created)
      expect(CbvFlowInvitation.last.client_agency_id).to eq("inv_only")
    end

    it "still requires the partner's invitation attributes" do
      create_api_invitation("inv_only", custom_attributes: full_attributes.except(:case_number))

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["errors"].first["field"]).to eq("custom_attributes.case_number")
    end

    it "starts a flow from the invitation link, going straight to consent" do
      create_api_invitation("inv_only", custom_attributes: full_attributes)
      invitation = CbvFlowInvitation.last

      get "/start/#{invitation.auth_token}"

      expect(response).to have_http_status(:ok)
      flow = CbvFlow.last
      expect(flow.cbv_flow_invitation).to eq(invitation)
      expect(flow).not_to be_generic
    end

    it "skips the applicant-information page, since the invitation carried everything" do
      create_api_invitation("inv_only", custom_attributes: every_attribute)
      get "/start/#{CbvFlowInvitation.last.auth_token}"

      get "/cbv/applicant_information"

      expect(response).to redirect_to("/cbv/summary")
    end

    it "offers no generic entry point" do
      host! "inv-only.verifymyincome.org"

      expect { get "/start" }.not_to change(CbvFlowInvitation, :count)
      expect(response).to redirect_to(root_url)
    end
  end

  describe "a partner that uses both invitations and generic links" do
    before { build_partner("both_ways", generic: true, invitations: true, landing_page: %w[case_number]) }

    it "still creates invitations through the API" do
      create_api_invitation("both_ways", custom_attributes: full_attributes)

      expect(response).to have_http_status(:created)
    end

    it "sends an invitation flow straight to consent, with no landing page" do
      create_api_invitation("both_ways", custom_attributes: full_attributes)

      get "/start/#{CbvFlowInvitation.last.auth_token}"

      expect(response).to have_http_status(:ok)
      expect(CbvFlow.last).not_to be_generic
    end

    it "auto-creates an invitation from the generic link" do
      host! "both-ways.verifymyincome.org"

      expect { get "/start" }.to change(CbvFlowInvitation, :count).by(1)
      expect(CbvFlowInvitation.last).to be_auto_created
      expect(response).to redirect_to(%r{/start/#{CbvFlowInvitation.last.auth_token}})
    end

    it "sends the generic flow to the landing page before consent" do
      host! "both-ways.verifymyincome.org"
      get "/start"
      follow_redirect!

      expect(response).to redirect_to("/en/cbv/landing_page")
      expect(CbvFlow.last).to be_generic
    end
  end

  describe "a partner that uses generic links only" do
    before { build_partner("gen_only", generic: true, invitations: false, landing_page: %w[case_number]) }

    it "auto-creates an invitation from the generic link" do
      host! "gen-only.verifymyincome.org"

      expect { get "/start" }.to change(CbvFlowInvitation, :count).by(1)
      expect(CbvFlowInvitation.last).to be_auto_created
    end

    it "collects the landing-page attribute, then reaches consent" do
      host! "gen-only.verifymyincome.org"
      get "/start"
      follow_redirect!
      follow_redirect!

      expect(response).to have_http_status(:ok)

      patch "/cbv/landing_page", params: { cbv_applicant: { cbv_applicant: { case_number: "9971" } } }

      expect(response).to redirect_to("/cbv/entry")
      expect(CbvFlow.last.cbv_applicant.case_number).to eq("9971")
    end

    it "refuses to create an invitation through the API" do
      expect { create_api_invitation("gen_only", custom_attributes: full_attributes) }
        .not_to change(CbvFlowInvitation, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
