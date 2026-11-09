require "rails_helper"

RSpec.describe AutoInvitationService do
  let(:event_logger) { instance_double(GenericEventTracker, track: nil) }
  let(:device_id) { SecureRandom.uuid }
  let(:service) { described_class.new(event_logger) }

  describe "#create_for" do
    it "creates an invitation owned by the partner's system account" do
      invitation = service.create_for(client_agency_id: "sandbox", device_id: device_id)

      expect(invitation).to be_persisted
      expect(invitation).to be_auto_created
      expect(invitation.user).to eq(User.system_account_for("sandbox"))
      expect(invitation.email_address).to eq(User.system_account_email_for("sandbox"))
    end

    it "reuses the same system account across calls" do
      expect {
        service.create_for(client_agency_id: "sandbox", device_id: device_id)
        service.create_for(client_agency_id: "sandbox", device_id: SecureRandom.uuid)
      }.to change(User, :count).by(1)
    end

    it "saves despite the partner's required applicant attributes being blank" do
      invitation = service.create_for(client_agency_id: "sandbox", device_id: device_id)

      expect(invitation.cbv_applicant.missing_required_attributes_for(PartnerAttributeUsage::INVITATION))
        .not_to be_empty
    end

    it "records the applicant's language on the invitation" do
      invitation = service.create_for(client_agency_id: "sandbox", device_id: device_id, language: :es)

      expect(invitation.language).to eq("es")
    end

    # A matching device cookie means a browser came back, not that the same
    # person did — so nothing is ever handed back, and each visit gets its own
    # invitation and its own applicant record.
    describe "never reusing a previous visit's invitation" do
      it "creates a fresh invitation even when this device already started one" do
        first = service.create_for(client_agency_id: "sandbox", device_id: device_id)
        create(:cbv_flow, :generic, cbv_flow_invitation: first,
               client_agency_id: "sandbox", device_id: device_id)

        second = nil
        expect { second = service.create_for(client_agency_id: "sandbox", device_id: device_id) }
          .to change(CbvFlowInvitation, :count).by(1)

        expect(second).not_to eq(first)
      end

      it "gives the new invitation its own applicant record" do
        first = service.create_for(client_agency_id: "sandbox", device_id: device_id)
        first.cbv_applicant.update!(case_number: "123456")

        second = service.create_for(client_agency_id: "sandbox", device_id: device_id)

        expect(second.cbv_applicant_id).not_to eq(first.cbv_applicant_id)
        expect(second.cbv_applicant.case_number).to be_nil
      end

      it "leaves a caseworker's invitation for this device untouched" do
        caseworker_invitation = create(:cbv_flow_invitation, client_agency_id: "sandbox")
        create(:cbv_flow, cbv_flow_invitation: caseworker_invitation,
               client_agency_id: "sandbox", device_id: device_id)

        invitation = service.create_for(client_agency_id: "sandbox", device_id: device_id)

        expect(invitation).not_to eq(caseworker_invitation)
        expect(invitation).to be_auto_created
      end
    end

    context "when the partner does not offer the generic flow" do
      it "creates nothing when generic links are disabled" do
        stub_client_agency_config_value("sandbox", "generic_links_enabled", false)

        result = nil
        expect { result = service.create_for(client_agency_id: "sandbox", device_id: device_id) }
          .not_to change(CbvFlowInvitation, :count)

        expect(result).to be_nil
      end

      it "creates nothing for an unknown partner" do
        expect { service.create_for(client_agency_id: "nope", device_id: device_id) }
          .not_to change(CbvFlowInvitation, :count)
      end
    end
  end
end
