require 'rails_helper'

RSpec.describe CbvFlow, type: :model do
  let(:cbv_flow) { create(:cbv_flow, client_agency_id: client_agency_id) }
  let(:client_agency_id) { "sandbox" }

  describe ".create_from_invitation" do
    let(:cbv_flow_invitation) { create(:cbv_flow_invitation, cbv_applicant_attributes: { case_number: "ABC1234" }) }

    it "copies over relevant fields" do
      cbv_flow = described_class.create_from_invitation(cbv_flow_invitation, "test_device_id")
      expect(cbv_flow).to have_attributes(
        cbv_applicant: cbv_flow_invitation.cbv_applicant,
        client_agency_id: "sandbox"
      )
    end
  end

  describe "#to_generic_url" do
    context "with valid client agency ID" do
      context "in production environment" do
        before do
          stub_client_agency_config_value("sandbox", "agency_domain", "sandbox.verifymyincome.org")
        end

        it "returns simplified URL with production domain" do
          expected_url = "https://sandbox.verifymyincome.org/en/start"
          expect(cbv_flow.to_generic_url).to eq(expected_url)
        end

        it "includes origin parameter when provided" do
          expected_url = "https://sandbox.verifymyincome.org/en/start?origin=shared"
          expect(cbv_flow.to_generic_url(origin: "shared")).to eq(expected_url)
        end
      end

      context "in non-production environment" do
        before do
          stub_client_agency_config_value("sandbox", "agency_domain", "demo.divt.app")
        end

        it "returns simplified URL with demo domain" do
          expected_url = "https://demo.divt.app/en/start"
          expect(cbv_flow.to_generic_url).to eq(expected_url)
        end
      end
    end

    context "with invalid client agency ID" do
      let(:cbv_flow) { build(:cbv_flow, client_agency_id: "invalid_agency") }

      it "raises ArgumentError" do
        expect { cbv_flow.to_generic_url }.to raise_error(
          ArgumentError, "Client Agency invalid_agency not found"
        )
      end
    end

    context "when the partner does not offer the generic flow" do
      before do
        stub_client_agency_config_value("sandbox", "agency_domain", "sandbox.verifymyincome.org")
        stub_client_agency_config_value("sandbox", "generic_links_enabled", false)
      end

      it "returns nil rather than advertising a link that would not work" do
        expect(cbv_flow.to_generic_url).to be_nil
      end
    end

    context "with missing host configuration" do
      before do
        stub_client_agency_config_value("sandbox", "agency_domain", nil)
      end

      it "returns nil, since the partner is identified by its subdomain" do
        expect(cbv_flow.to_generic_url).to be_nil
        expect(cbv_flow.to_generic_url(origin: "shared")).to be_nil
      end
    end
  end

  describe "#fully_synced_payroll_accounts" do
    it "returns only those payroll accounts that have fully synced" do
      create(:payroll_account, cbv_flow: cbv_flow)
      create(:payroll_account, :pinwheel_fully_synced, cbv_flow: cbv_flow)
      create(:payroll_account, :argyle_sync_in_progress, cbv_flow: cbv_flow)
      create(:payroll_account, :argyle_fully_synced, cbv_flow: cbv_flow)

      result = cbv_flow.fully_synced_payroll_accounts

      expect(result).to all(be_has_fully_synced)
      expect(result).not_to be_empty
    end
  end
end
