require "rails_helper"

RSpec.describe CbvInvitationService, type: :service do
  let(:event_logger) { instance_double(GenericEventTracker) }
  let(:service) { described_class.new(event_logger) }
  let(:cbv_flow_invitation_params) do
    attributes_for(:cbv_flow_invitation).merge(
      cbv_applicant_attributes: attributes_for(:cbv_applicant)
    )
  end
  let(:current_user) { create(:user) }

  before do
    allow(event_logger).to receive(:track)
  end

  describe '#invite' do
    context 'when delivery method is :email' do
      it 'creates an invitation with correct parameters' do
        service.invite(
          cbv_flow_invitation_params,
          current_user,
          communication_channel: :email
        )

        invitation = CbvFlowInvitation.last
        expect(invitation.user).to eq(current_user)
        expect(invitation.cbv_applicant.case_number).to eq(
          cbv_flow_invitation_params[:cbv_applicant_attributes][:case_number]
        )
      end

      it 'sends an email invitation' do
        expect do
          service.invite(
            cbv_flow_invitation_params,
            current_user,
            communication_channel: :email
          )
        end.to change { ActionMailer::Base.deliveries.count }
          .by(1)

        email = ActionMailer::Base.deliveries.last
        expect(email.to).to include(cbv_flow_invitation_params[:email_address])
      end

      it 'tracks the event' do
        service.invite(
          cbv_flow_invitation_params,
          current_user,
          communication_channel: :email
        )

        invitation = CbvFlowInvitation.last
        expect(event_logger).to have_received(:track).with(
          'CaseworkerInvitedApplicantToFlow',
          nil,
          hash_including(invitation_id: invitation.id)
        )
      end
    end

    context 'when delivery method is nil' do
      it 'creates an invitation with correct parameters' do
        service.invite(
          cbv_flow_invitation_params,
          current_user,
          communication_channel: nil
        )

        invitation = CbvFlowInvitation.last
        expect(invitation.user).to eq(current_user)
        expect(invitation.cbv_applicant.case_number).to eq(
          cbv_flow_invitation_params[:cbv_applicant_attributes][:case_number]
        )
      end

      it 'logs a message instead of sending an email' do
        allow(Rails.logger).to receive(:info)

        expect do
          service.invite(
            cbv_flow_invitation_params,
            current_user,
            communication_channel: nil
          )
        end.not_to change { ActionMailer::Base.deliveries.count }

        expect(Rails.logger).to have_received(:info).with(/Generated invitation ID:/)
      end

      it 'tracks the event' do
        service.invite(
          cbv_flow_invitation_params,
          current_user,
          communication_channel: nil
        )

        invitation = CbvFlowInvitation.last
        expect(event_logger).to have_received(:track).with(
          'CaseworkerInvitedApplicantToFlow',
          nil,
          hash_including(invitation_id: invitation.id)
        )
      end
    end

    context 'when the communication channel is :sms' do
      let(:sms_invitation_params) do
        cbv_flow_invitation_params.merge(email_address: nil, phone_number: "555-234-5678")
      end

      it 'creates a communication row and enqueues the SMS job' do
        invitation = nil
        expect do
          invitation = service.invite(
            sms_invitation_params,
            current_user,
            communication_channel: :sms
          )
        end.to have_enqueued_job(InvitationSmsJob)

        communication = invitation.invitation_communications.last
        expect(communication.channel).to eq("sms")
        expect(communication.status).to eq("created")
        expect(InvitationSmsJob).to have_been_enqueued.with(communication.id)
      end

      it 'does not send an email' do
        expect do
          service.invite(sms_invitation_params, current_user, communication_channel: :sms)
        end.not_to change { ActionMailer::Base.deliveries.count }
      end

      it 'tracks the enqueued event' do
        invitation = service.invite(sms_invitation_params, current_user, communication_channel: :sms)

        expect(event_logger).to have_received(:track).with(
          'SmsEnqueued',
          nil,
          hash_including(
            invitation_id: invitation.id,
            invitation_communication_id: invitation.invitation_communications.last.id
          )
        )
      end

      it 'requires a phone number' do
        invitation = service.invite(
          sms_invitation_params.merge(phone_number: nil),
          current_user,
          communication_channel: :sms
        )

        expect(invitation.errors[:phone_number]).to be_present
        expect(invitation.invitation_communications).to be_empty
      end
    end

    context 'metrics_attributes' do
      it 'merges supplied metrics_attributes into the tracked event' do
        service.invite(
          cbv_flow_invitation_params,
          current_user,
          communication_channel: nil,
          metrics_attributes: { "source" => "ops_console", "campaign" => "spring2026" }
        )

        expect(event_logger).to have_received(:track).with(
          'CaseworkerInvitedApplicantToFlow',
          nil,
          hash_including("source" => "ops_console", "campaign" => "spring2026")
        )
      end

      it 'does not let metrics_attributes overwrite system-set properties' do
        service.invite(
          cbv_flow_invitation_params,
          current_user,
          communication_channel: nil,
          metrics_attributes: { invitation_id: "spoofed", user_id: "spoofed" }
        )

        invitation = CbvFlowInvitation.last
        expect(event_logger).to have_received(:track).with(
          'CaseworkerInvitedApplicantToFlow',
          nil,
          hash_including(invitation_id: invitation.id, user_id: current_user.id)
        )
      end

      it 'still tracks the event when metrics_attributes is empty or omitted' do
        service.invite(cbv_flow_invitation_params, current_user, communication_channel: nil)

        expect(event_logger).to have_received(:track).with(
          'CaseworkerInvitedApplicantToFlow',
          nil,
          hash_including(:invitation_id)
        )
      end
    end
  end
end
