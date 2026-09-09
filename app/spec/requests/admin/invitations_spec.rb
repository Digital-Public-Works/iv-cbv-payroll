require "rails_helper"

RSpec::Matchers.define_negated_matcher :not_change, :change

RSpec.describe "Admin invitations", type: :request do
  let(:applicant_attributes) { attributes_for(:cbv_applicant, :sandbox).except(:created_at) }
  let(:link_params) do
    {
      cbv_flow_invitation: {
        language: "en",
        communication_channel: "link",
        cbv_applicant_attributes: applicant_attributes
      }
    }
  end
  let(:sms_params) do
    {
      sms_attestation: "1",
      cbv_flow_invitation: {
        language: "en",
        communication_channel: "sms",
        phone_number: "(555) 234-5678",
        cbv_applicant_attributes: applicant_attributes
      }
    }
  end

  before do
    post admin_agency_selection_path, params: { client_agency_id: "sandbox" }
  end

  describe "portal availability" do
    it "does not route when the portal is disabled" do
      allow(Rails.application.config).to receive(:admin_portal_enabled).and_return(false)

      get admin_root_path

      expect(response).to have_http_status(:not_found)
    end

    it "renders the home page when enabled" do
      get admin_root_path

      expect(response).to be_successful
      expect(response.body).to include("Invitation tools")
    end
  end

  describe "POST /admin/invitations" do
    context "with the link channel" do
      it "creates an invitation owned by the agency's system user and redirects to its page" do
        expect do
          post admin_invitations_path, params: link_params
        end.to change(CbvFlowInvitation, :count).by(1)
          .and not_change(InvitationCommunication, :count)

        invitation = CbvFlowInvitation.last
        expect(invitation.user.email).to eq(User::ADMIN_SYSTEM_USER_EMAIL)
        expect(invitation.client_agency_id).to eq("sandbox")
        expect(response).to redirect_to(admin_invitation_path(id: invitation.id))
      end
    end

    context "with the sms channel" do
      it "creates a communication and enqueues the SMS job" do
        expect do
          post admin_invitations_path, params: sms_params
        end.to change(InvitationCommunication, :count).by(1)
          .and have_enqueued_job(InvitationSmsJob)

        invitation = CbvFlowInvitation.last
        expect(invitation.phone_number).to eq("+15552345678")
        expect(invitation.invitation_communications.last.channel).to eq("sms")
      end

      it "requires the attestation checkbox" do
        expect do
          post admin_invitations_path, params: sms_params.except(:sms_attestation)
        end.not_to change(CbvFlowInvitation, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Confirm the applicant has agreed")
      end

      it "requires a valid phone number" do
        sms_params[:cbv_flow_invitation][:phone_number] = "not-a-number"

        expect do
          post admin_invitations_path, params: sms_params
        end.not_to change(CbvFlowInvitation, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /admin/invitations/:id" do
    it "shows the copyable link and status board" do
      post admin_invitations_path, params: sms_params
      invitation = CbvFlowInvitation.last

      get admin_invitation_path(id: invitation.id)

      expect(response).to be_successful
      expect(response.body).to include(invitation.to_url)
      expect(response.body).to include("Invitation #{invitation.id}")
      expect(response.body).to include("Message #{invitation.invitation_communications.last.id}")
      expect(response.body).to include("data-polling-url-value")
    end

    it "does not expose invitations that were not created through the portal" do
      other_invitation = create(:cbv_flow_invitation, :sandbox)

      get admin_invitation_path(id: other_invitation.id)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /admin/invitations/:id/status" do
    it "returns a turbo stream replacing the status board" do
      post admin_invitations_path, params: sms_params
      invitation = CbvFlowInvitation.last

      patch status_admin_invitation_path(id: invitation.id),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to be_successful
      expect(response.body).to include('turbo-stream action="replace" target="invitation_status"')
    end

    it "marks the response complete once the send has failed" do
      post admin_invitations_path, params: sms_params
      invitation = CbvFlowInvitation.last
      invitation.invitation_communications.last.update!(status: :failed, last_error: "Twilio error 21211")

      patch status_admin_invitation_path(id: invitation.id),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.body).to include("data-polling-complete")
      expect(response.body).to include("Twilio error 21211")
    end
  end

  describe "POST /admin/invitations/:id/resend" do
    it "creates a fresh communication for a failed send and enqueues the job" do
      post admin_invitations_path, params: sms_params
      invitation = CbvFlowInvitation.last
      failed = invitation.invitation_communications.last
      failed.update!(status: :failed, last_error: "Twilio error 20003")

      expect do
        post resend_admin_invitation_path(id: invitation.id)
      end.to change(invitation.invitation_communications, :count).by(1)
        .and have_enqueued_job(InvitationSmsJob)

      retry_communication = invitation.invitation_communications.order(:created_at).last
      expect(InvitationSmsJob).to have_been_enqueued.with(retry_communication.id)
      expect(retry_communication.status).to eq("created")
      expect(failed.reload.status).to eq("failed")
      expect(response).to redirect_to(admin_invitation_path(id: invitation.id))
    end

    it "does not re-send when the latest communication has not failed" do
      post admin_invitations_path, params: sms_params
      invitation = CbvFlowInvitation.last

      expect do
        post resend_admin_invitation_path(id: invitation.id)
      end.to not_change(invitation.invitation_communications, :count)

      expect(response).to redirect_to(admin_invitation_path(id: invitation.id))
    end

    it "shows the retry button on a failed status board" do
      post admin_invitations_path, params: sms_params
      invitation = CbvFlowInvitation.last
      invitation.invitation_communications.last.update!(status: :failed, last_error: "boom")

      get admin_invitation_path(id: invitation.id)

      expect(response.body).to include(resend_admin_invitation_path(id: invitation.id))
      expect(response.body).to include("Send text message again")
    end
  end

  describe "GET /admin/invitations" do
    it "lists only the selected agency's portal invitations from the last 24 hours" do
      post admin_invitations_path, params: sms_params
      recent = CbvFlowInvitation.last

      old = create(:cbv_flow_invitation, :sandbox, user: User.admin_system_user_for("sandbox"))
      old.update_column(:created_at, 2.days.ago)

      get admin_invitations_path

      expect(response).to be_successful
      expect(response.body).to include(admin_invitation_path(id: recent.id))
      expect(response.body).not_to include(admin_invitation_path(id: old.id))
      expect(response.body).to include("···5678")
    end

    it "scopes to the agency selected in the session" do
      post admin_invitations_path, params: sms_params

      post admin_agency_selection_path, params: { client_agency_id: "az_des" }
      get admin_invitations_path

      expect(response.body).not_to include("···5678")
    end
  end
end
