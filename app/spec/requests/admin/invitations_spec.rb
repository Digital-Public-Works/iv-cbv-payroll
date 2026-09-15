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
    host! "sandbox.example.com"
  end

  describe "portal availability" do
    it "does not route when the portal is disabled" do
      allow(Rails.application.config).to receive(:admin_portal_enabled).and_return(false)

      get admin_root_path

      expect(response).to have_http_status(:not_found)
    end

    it "renders the invitations list as the portal home" do
      get admin_root_path

      expect(response).to be_successful
      expect(response.body).to include("Invitations from the last 24 hours")
      expect(response.body).to include("VMI Caseworker Portal")
    end

    it "redirects the bare domain to the agency sitemap" do
      host! "www.example.com"

      get admin_root_path
      expect(response).to redirect_to(admin_agencies_path)

      get admin_agencies_path
      expect(response).to be_successful
      expect(response.body).to include("Agency portals")
      expect(response.body).to include("sandbox.")
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

  describe "POST /admin/invitations with the email channel" do
    let(:email_params) do
      {
        cbv_flow_invitation: {
          language: "en",
          communication_channel: "email",
          email_address: "applicant@example.com",
          cbv_applicant_attributes: applicant_attributes
        }
      }
    end

    it "creates a communication and enqueues the email job" do
      expect do
        post admin_invitations_path, params: email_params
      end.to change(InvitationCommunication, :count).by(1)
        .and have_enqueued_job(InvitationEmailJob)

      invitation = CbvFlowInvitation.last
      expect(invitation.email_address).to eq("applicant@example.com")
      expect(invitation.invitation_communications.last.channel).to eq("email")
      expect(response).to redirect_to(admin_invitation_path(id: invitation.id))
    end

    it "requires an email address" do
      email_params[:cbv_flow_invitation][:email_address] = ""

      expect do
        post admin_invitations_path, params: email_params
      end.not_to change(CbvFlowInvitation, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "does not require the attestation checkbox" do
      post admin_invitations_path, params: email_params

      expect(response).to have_http_status(:redirect)
    end

    it "resends a failed email through the email job" do
      post admin_invitations_path, params: email_params
      invitation = CbvFlowInvitation.last
      invitation.invitation_communications.last.update!(status: :failed, last_error: "boom")

      expect do
        post resend_admin_invitation_path(id: invitation.id)
      end.to change(invitation.invitation_communications, :count).by(1)

      expect(InvitationEmailJob).to have_been_enqueued.with(invitation.invitation_communications.order(:created_at).last.id)
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
      invitation.invitation_communications.last.update!(status: :failed, last_error: "SNS error InvalidParameter")

      patch status_admin_invitation_path(id: invitation.id),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.body).to include("data-polling-complete")
      expect(response.body).to include("SNS error InvalidParameter")
    end
  end

  describe "POST /admin/invitations/:id/resend" do
    it "creates a fresh communication for a failed send and enqueues the job" do
      post admin_invitations_path, params: sms_params
      invitation = CbvFlowInvitation.last
      failed = invitation.invitation_communications.last
      failed.update!(status: :failed, last_error: "SNS error AuthorizationError")

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

    it "shows AM/PM agency-timezone timestamps and the email domain as destination" do
      post admin_invitations_path, params: {
        cbv_flow_invitation: {
          language: "en",
          communication_channel: "email",
          email_address: "applicant@example.com",
          cbv_applicant_attributes: applicant_attributes
        }
      }

      get admin_invitations_path

      expect(response.body).to match(/\b(AM|PM)\b/)
      expect(response.body).to include("@example.com")
    end

    it "scopes to the agency inferred from the subdomain" do
      post admin_invitations_path, params: sms_params

      host! "az.example.com"
      get admin_invitations_path

      expect(response.body).not_to include("···5678")
    end
  end
end
