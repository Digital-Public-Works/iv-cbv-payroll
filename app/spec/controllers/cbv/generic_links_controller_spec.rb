require "rails_helper"

RSpec.describe Cbv::GenericLinksController do
  before do
    allow(MixpanelEventTrackingJob).to receive(:perform_later)
  end

  describe '#show' do
    context 'when the hostname matches a client agency domain' do
      before do
        stub_client_agency_config_value("sandbox", "generic_links_enabled", true)
        request.host = "sandbox.verifymyincome.org"
      end

      context 'when generic links are disabled for the agency' do
        before do
          stub_client_agency_config_value("sandbox", "generic_links_enabled", false)
        end

        it 'redirects to the root path' do
          get :show
          expect(response).to redirect_to(root_path)
        end

        it 'does not create an invitation' do
          expect { get :show }
            .not_to change(CbvFlowInvitation, :count)
        end
      end

      context 'when this device has no invitation yet' do
        let(:headers) { {} }

        before do
          request.headers.merge!(headers)
          get :show
        end

        it "auto-creates an invitation and redirects to its tokenized link" do
          invitation = CbvFlowInvitation.last

          expect(invitation.client_agency_id).to eq("sandbox")
          expect(invitation).to be_auto_created
          expect(response).to redirect_to(start_flow_path(token: invitation.auth_token, locale: I18n.locale))
        end

        it "owns the invitation with the partner's system account rather than a caseworker" do
          invitation = CbvFlowInvitation.last

          expect(invitation.user).to eq(User.system_account_for("sandbox"))
          expect(invitation.user).to be_system_account
        end

        it "saves the invitation even though no required applicant attribute has a value" do
          invitation = CbvFlowInvitation.last

          expect(invitation).to be_persisted
          expect(invitation.cbv_applicant.missing_required_attributes_for(PartnerAttributeUsage::INVITATION)).not_to be_empty
        end

        it "tracks ApplicantClickedGenericLink event with is_new_session: true" do
          expect(MixpanelEventTrackingJob).to have_received(:perform_later).with(
            "ApplicantClickedGenericLink",
            anything,
            hash_including(
              invitation_id: CbvFlowInvitation.last.id,
              cbv_applicant_id: CbvFlowInvitation.last.cbv_applicant_id,
              client_agency_id: "sandbox",
              is_new_session: true
            )
          )
        end

        it "tracks ApplicantAutoCreatedInvitation" do
          expect(MixpanelEventTrackingJob).to have_received(:perform_later).with(
            "ApplicantAutoCreatedInvitation",
            anything,
            hash_including(invitation_id: CbvFlowInvitation.last.id)
          )
        end

        context "when the User Agent is nil" do
          let(:headers) { { "User-Agent" => nil } }

          it "tracks the ApplicantClickedGenericLink event" do
            expect(MixpanelEventTrackingJob).to have_received(:perform_later)
              .with("ApplicantClickedGenericLink", anything, anything)
          end
        end

        context "when the User Agent is Go-Http-Client" do
          let(:headers) { { "User-Agent" => "Go-http-client/1.1" } }

          it "does not track the ApplicantClickedGenericLink event" do
            expect(MixpanelEventTrackingJob).not_to have_received(:perform_later)
              .with("ApplicantClickedGenericLink", anything, anything)
          end
        end
      end

      # A matching device cookie says a browser came back, not that the same
      # person did, so nothing from a previous visit is ever handed back.
      context 'when this device already started a flow on an earlier invitation' do
        let(:device_id) { SecureRandom.uuid }
        let!(:invitation) { create(:cbv_flow_invitation, :auto_created) }

        before do
          create(:cbv_flow,
            :generic,
            cbv_flow_invitation: invitation,
            client_agency_id: "sandbox",
            device_id: device_id)

          cookies.signed[:device_id] = device_id
        end

        it "generates a new invitation rather than handing back the earlier one" do
          expect { get :show }.to change(CbvFlowInvitation, :count).by(1)

          expect(CbvFlowInvitation.last).not_to eq(invitation)
          expect(response).to redirect_to(
            start_flow_path(token: CbvFlowInvitation.last.auth_token, locale: I18n.locale)
          )
        end

        it "gives it a fresh applicant record, carrying nothing over" do
          invitation.cbv_applicant.update!(first_name: "John")

          get :show

          expect(CbvFlowInvitation.last.cbv_applicant_id).not_to eq(invitation.cbv_applicant_id)
          expect(CbvFlowInvitation.last.cbv_applicant.first_name).to be_nil
        end

        it "leaves the earlier invitation's data alone" do
          invitation.cbv_applicant.update!(first_name: "John")

          get :show

          expect(invitation.cbv_applicant.reload.first_name).to eq("John")
        end
      end

      context 'when origin parameter is provided' do
        before do
          get :show, params: { origin: "mail" }
        end

        it "includes origin in tracking event" do
          expect(MixpanelEventTrackingJob).to have_received(:perform_later).with(
            "ApplicantClickedGenericLink",
            anything,
            hash_including(origin: "mail")
          )
        end

        it "carries the origin through to the tokenized link" do
          expect(response).to redirect_to(
            start_flow_path(token: CbvFlowInvitation.last.auth_token, locale: I18n.locale, origin: "mail")
          )
        end
      end
    end

    context 'when the hostname resolves to no partner' do
      it "redirects to the landing page without creating an invitation" do
        request.host = "www.verifymyincome.org"

        expect { get :show }.not_to change(CbvFlowInvitation, :count)
        expect(response).to redirect_to(root_url)
      end
    end
  end
end
