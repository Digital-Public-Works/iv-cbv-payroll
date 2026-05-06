require "rails_helper"

RSpec.describe DataRetentionService do
  describe "#redact_invitations" do
    let!(:cbv_flow_invitation) do
      create(:cbv_flow_invitation, :sandbox)
    end
    let(:service) { DataRetentionService.new }
    let(:now) { Time.now }

    around do |ex|
      Timecop.freeze(now, &ex)
    end

    context "for an unused invitation (no associated CbvFlow)" do
      context "before the deletion threshold" do
        let(:now) { cbv_flow_invitation.expires_at + 7.days - 1.minute }

        it "does not redact the invitation" do
          expect { service.redact_invitations }
            .not_to change { cbv_flow_invitation.reload.attributes }
        end
      end

      context "after the deletion threshold" do
        let(:now) { cbv_flow_invitation.expires_at + 7.days + 1.minute }

        it "redacts the invitation" do
          service.redact_invitations
          expect(cbv_flow_invitation.reload).to have_attributes(
            email_address: "REDACTED@example.com",
            auth_token: "REDACTED",
            redacted_at: within(1.second).of(Time.now)
          )
        end

        it "redacts the associated CbvApplicant" do
          service.redact_invitations
          expect(cbv_flow_invitation.cbv_applicant.reload).to have_attributes(
            first_name: "REDACTED",
            redacted_at: within(1.second).of(Time.now)
          )
        end

        it "skips the invitation if it has already been redacted" do
          cbv_flow_invitation.redact!

          expect_any_instance_of(CbvFlowInvitation)
            .not_to receive(:redact!)
          service.redact_invitations
        end
      end
    end
  end

  describe "#redact_incomplete_cbv_flows" do
    let!(:cbv_flow_invitation) do
      create(:cbv_flow_invitation)
    end
    let!(:cbv_flow) { CbvFlow.create_from_invitation(cbv_flow_invitation, "test_device_id") }
    let(:service) { DataRetentionService.new }
    let(:deletion_threshold) { cbv_flow_invitation.expires_at + DataRetentionService::REDACT_UNUSED_INVITATIONS_AFTER }
    let(:now) { Time.now }

    around do |ex|
      Timecop.freeze(now, &ex)
    end

    context "before the deletion threshold" do
      let(:now) { deletion_threshold - 1.minute }

      it "does not redact the CbvFlow" do
        expect { service.redact_incomplete_cbv_flows }
          .not_to change { cbv_flow.reload.attributes }
      end

      it "does not redact the CbvFlowInvitation" do
        expect { service.redact_incomplete_cbv_flows }
          .not_to change { cbv_flow_invitation.reload.attributes }
      end

      it "does not redact the CbvApplicant" do
        expect { service.redact_incomplete_cbv_flows }
          .not_to change { cbv_flow.cbv_applicant.reload.attributes }
      end

      it "does not redact an associated PayrollAccount" do
        payroll_account = create(:payroll_account, cbv_flow: cbv_flow)

        expect { service.redact_incomplete_cbv_flows }
          .not_to change { payroll_account.reload.attributes }
      end
    end

    context "after the deletion threshold" do
      let(:now) { deletion_threshold + 1.minute }

      before do
        cbv_flow.update(
          end_user_id: "11111111-1111-1111-1111-111111111111",
          additional_information: { "account-id" => "some string here" }
        )
      end

      it "redacts the incomplete CbvFlow" do
        service.redact_incomplete_cbv_flows
        expect(cbv_flow.reload).to have_attributes(
          end_user_id: "00000000-0000-0000-0000-000000000000",
          additional_information: {}
        )
      end

      it "redacts the associated invitation" do
        service.redact_incomplete_cbv_flows
        expect(cbv_flow_invitation.reload).to have_attributes(
          auth_token: "REDACTED",
          redacted_at: within(1.second).of(now)
        )
      end

      it "redacts the associated CbvApplicant" do
        service.redact_incomplete_cbv_flows
        expect(cbv_flow.cbv_applicant.reload).to have_attributes(
          first_name: "REDACTED"
        )
      end

      it "redacts an associated PayrollAccount" do
        payroll_account = create(:payroll_account, cbv_flow: cbv_flow)
        service.redact_incomplete_cbv_flows
        expect(payroll_account.reload).to have_attributes(
          redacted_at: within(1.second).of(now)
        )
      end

      it "skips redacting already-redacted CbvFlows" do
        service.redact_incomplete_cbv_flows

        expect_any_instance_of(CbvFlow).not_to receive(:redact!)
        service.redact_incomplete_cbv_flows
      end

      context "for a complete CbvFlow" do
        before do
          cbv_flow.update(confirmation_code: "SANDBOX001")
        end

        it "does not redact the CbvFlow" do
          expect { service.redact_invitations }
            .not_to change { cbv_flow.reload.attributes }
        end

        it "does not redact the invitation" do
          expect { service.redact_invitations }
            .not_to change { cbv_flow_invitation.reload.attributes }
        end
      end

      context "when the cbv_flow has an argyle_user_id" do
        let(:fake_argyle) { instance_double(Aggregators::Sdk::ArgyleService) }

        before do
          cbv_flow.update(argyle_user_id: "argyle_123")

          argyle_environment = ClientAgencyConfig.instance[cbv_flow.client_agency_id].argyle_environment
          allow(Aggregators::Sdk::ArgyleService)
            .to receive(:new)
                  .with(argyle_environment)
                  .and_return(fake_argyle)

          allow(fake_argyle).to receive(:delete_user)
        end

        it "deletes the argyle user" do
          expect(fake_argyle).to receive(:delete_user).with(argyle_user_id: "argyle_123")
          service.redact_incomplete_cbv_flows
        end
      end
    end

    context "when the CbvFlow has no invitation" do
      let(:cbv_flow) { create(:cbv_flow, :invited, cbv_flow_invitation: nil) }
      let(:deletion_threshold) { cbv_flow.updated_at + DataRetentionService::REDACT_UNUSED_INVITATIONS_AFTER }

      context "before the deletion threshold" do
        let(:now) { deletion_threshold - 1.minute }

        it "does not redact the CbvFlow" do
          expect { service.redact_invitations }
            .not_to change { cbv_flow.reload.attributes }
        end
      end

      context "after the deletion threshold" do
        let(:now) { deletion_threshold + 1.minute }

        it "redacts the incomplete CbvFlow" do
          service.redact_incomplete_cbv_flows
          expect(cbv_flow.reload).to have_attributes(
            end_user_id: "00000000-0000-0000-0000-000000000000",
            additional_information: {}
          )
        end

        it "redacts an associated PayrollAccount" do
          payroll_account = create(:payroll_account, cbv_flow: cbv_flow)
          service.redact_incomplete_cbv_flows
          expect(payroll_account.reload).to have_attributes(
            redacted_at: within(1.second).of(now)
          )
        end
      end
    end
  end

  describe "#redact_transmitted_cbv_flows" do
    let!(:cbv_flow_invitation) do
      create(:cbv_flow_invitation)
    end
    let!(:cbv_flow) do
      CbvFlow
        .create_from_invitation(cbv_flow_invitation, "test_device_id")
        .tap do |cbv_flow|
          cbv_flow.update(
            end_user_id: "11111111-1111-1111-1111-111111111111",
            additional_information: { "account-id" => "some string here" },
            confirmation_code: "SANDBOX0002",
            transmitted_at: Time.new(2024, 8, 1, 12, 0, 0, "-04:00")
          )
        end
    end
    let(:service) { DataRetentionService.new }
    let(:deletion_threshold) { cbv_flow.transmitted_at + DataRetentionService::REDACT_TRANSMITTED_CBV_FLOWS_AFTER }
    let(:now) { Time.now }

    around do |ex|
      Timecop.freeze(now, &ex)
    end

    context "before the deletion threshold" do
      let(:now) { deletion_threshold - 1.minute }

      it "does not redact the CbvFlow" do
        expect { service.redact_transmitted_cbv_flows }
          .not_to change { cbv_flow.reload.attributes }
      end

      it "does not redact the CbvFlowInvitation" do
        expect { service.redact_transmitted_cbv_flows }
          .not_to change { cbv_flow_invitation.reload.attributes }
      end

      it "does not redact the CbvApplicant" do
        expect { service.redact_transmitted_cbv_flows }
          .not_to change { cbv_flow.cbv_applicant.reload.attributes }
      end

      it "does not redact an associated PayrollAccount" do
        payroll_account = create(:payroll_account, cbv_flow: cbv_flow)

        expect { service.redact_transmitted_cbv_flows }
          .not_to change { payroll_account.reload.attributes }
      end
    end

    context "after the deletion threshold" do
      let(:now) { deletion_threshold + 1.minute }

      it "redacts the incomplete CbvFlow" do
        service.redact_transmitted_cbv_flows
        expect(cbv_flow.reload).to have_attributes(
          end_user_id: "00000000-0000-0000-0000-000000000000",
          additional_information: {}
        )
      end

      it "redacts the associated invitation" do
        service.redact_transmitted_cbv_flows
        expect(cbv_flow_invitation.reload).to have_attributes(
          auth_token: "REDACTED",
          redacted_at: within(1.second).of(now)
        )
      end

      it "redacts the associated applicant" do
        service.redact_transmitted_cbv_flows
        expect(cbv_flow.cbv_applicant.reload).to have_attributes(
          first_name: "REDACTED"
        )
      end

      it "redacts an associated PayrollAccount" do
        payroll_account = create(:payroll_account, cbv_flow: cbv_flow)
        service.redact_transmitted_cbv_flows
        expect(payroll_account.reload).to have_attributes(
          redacted_at: within(1.second).of(now)
        )
      end

      it "skips redacting already-redacted CbvFlows" do
        service.redact_transmitted_cbv_flows

        expect_any_instance_of(CbvFlow).not_to receive(:redact!)
        service.redact_transmitted_cbv_flows
      end

      context "when the cbv_flow has an argyle_user_id" do
        let(:fake_argyle) { instance_double(Aggregators::Sdk::ArgyleService) }

        before do
          cbv_flow.update(argyle_user_id: "argyle_123")

          argyle_environment = ClientAgencyConfig.instance[cbv_flow.client_agency_id].argyle_environment
          allow(Aggregators::Sdk::ArgyleService)
            .to receive(:new)
                  .with(argyle_environment)
                  .and_return(fake_argyle)

          allow(fake_argyle).to receive(:delete_user)
        end

        it "deletes the argyle user" do
          expect(fake_argyle).to receive(:delete_user).with(argyle_user_id: "argyle_123")
          service.redact_transmitted_cbv_flows
        end
      end

      context "when the cbv_flow has no argyle_user_id" do
        before do
          cbv_flow.update(argyle_user_id: nil)
        end

        it "does not attempt to delete argyle user" do
          expect(service).not_to receive(:delete_argyle_user)
          service.redact_transmitted_cbv_flows
        end
      end
    end
  end

  describe "#redact_old_cbv_flows" do
    let!(:cbv_flow_invitation) do
      create(:cbv_flow_invitation)
    end
    let!(:cbv_flow) do
      CbvFlow
        .create_from_invitation(cbv_flow_invitation, 'test_device_id')
        .tap do |cbv_flow|
        cbv_flow.update(
          end_user_id: "11111111-1111-1111-1111-111111111111",
          additional_information: { "account-id" => "some string here" },
          confirmation_code: "SANDBOX0002",
          created_at: Time.new(2024, 8, 1, 12, 0, 0, "-04:00")
        )
      end
    end
    let(:service) { DataRetentionService.new }
    let(:deletion_threshold) { cbv_flow.created_at + DataRetentionService::REDACT_OLD_RECORD_BACKSTOP }
    let(:now) { Time.now }

    around do |ex|
      Timecop.freeze(now, &ex)
    end

    context "before the deletion threshold" do
      let(:now) { deletion_threshold - 1.minute }

      it "does not redact the CbvFlow" do
        expect { service.redact_old_cbv_flows }
          .not_to change { cbv_flow.reload.attributes }
      end

      it "does not redact the CbvFlowInvitation" do
        expect { service.redact_old_cbv_flows }
          .not_to change { cbv_flow_invitation.reload.attributes }
      end

      it "does not redact the CbvApplicant" do
        expect { service.redact_old_cbv_flows }
          .not_to change { cbv_flow.cbv_applicant.reload.attributes }
      end

      it "does not redact an associated PayrollAccount" do
        payroll_account = create(:payroll_account, cbv_flow: cbv_flow)

        expect { service.redact_old_cbv_flows }
          .not_to change { payroll_account.reload.attributes }
      end
    end

    context "after the deletion threshold" do
      let(:now) { deletion_threshold + 1.minute }

      it "redacts the incomplete CbvFlow" do
        service.redact_old_cbv_flows
        expect(cbv_flow.reload).to have_attributes(
                                     end_user_id: "00000000-0000-0000-0000-000000000000",
                                     additional_information: {}
                                   )
      end

      it "redacts the associated invitation" do
        service.redact_old_cbv_flows
        expect(cbv_flow_invitation.reload).to have_attributes(
                                                auth_token: "REDACTED",
                                                redacted_at: within(1.second).of(now)
                                              )
      end

      it "redacts the associated applicant" do
        service.redact_old_cbv_flows
        expect(cbv_flow.cbv_applicant.reload).to have_attributes(
                                                   first_name: "REDACTED"
                                                 )
      end

      it "redacts an associated PayrollAccount" do
        payroll_account = create(:payroll_account, cbv_flow: cbv_flow)
        service.redact_old_cbv_flows
        expect(payroll_account.reload).to have_attributes(
                                            redacted_at: within(1.second).of(now)
                                          )
      end

      it "skips redacting already-redacted CbvFlows" do
        service.redact_old_cbv_flows

        expect_any_instance_of(CbvFlow).not_to receive(:redact!)
        service.redact_old_cbv_flows
      end

      context "when the cbv_flow has an argyle_user_id" do
        let(:fake_argyle) { instance_double(Aggregators::Sdk::ArgyleService) }

        before do
          cbv_flow.update(argyle_user_id: "argyle_123")

          argyle_environment = ClientAgencyConfig.instance[cbv_flow.client_agency_id].argyle_environment
          allow(Aggregators::Sdk::ArgyleService)
            .to receive(:new)
                  .with(argyle_environment)
                  .and_return(fake_argyle)

          allow(fake_argyle).to receive(:delete_user)
        end

        it "deletes the argyle user" do
          expect(fake_argyle).to receive(:delete_user).with(argyle_user_id: "argyle_123")
          service.redact_old_cbv_flows
        end
      end
    end
  end

  describe "#delete_argyle_user" do
    let(:argyle_user_id) { "argyle_123" }
    let(:client_agency_id) { "sandbox" }
    let(:service) { DataRetentionService.new }
    let(:argyle_service) { instance_double(Aggregators::Sdk::ArgyleService) }
    let(:argyle_environment) { "sandbox" }
    let(:client_agency_double) { instance_double("ClientAgencyConfig::ClientAgency", argyle_environment: argyle_environment) }

    before do
      # Mock the config lookup
      allow(ClientAgencyConfig.instance).to receive(:[])
        .with(client_agency_id)
        .and_return(client_agency_double)
      allow(Aggregators::Sdk::ArgyleService).to receive(:new).with(argyle_environment).and_return(argyle_service)
    end

    it "initializes ArgyleService with the correct environment" do
      allow(argyle_service).to receive(:delete_user)

      expect(Aggregators::Sdk::ArgyleService).to receive(:new).with(argyle_environment)
      service.send(:delete_argyle_user, client_agency_id, argyle_user_id)
    end

    it "calls delete_user with the correct user_id" do
      expect(argyle_service).to receive(:delete_user).with(argyle_user_id: argyle_user_id)
      service.send(:delete_argyle_user, client_agency_id, argyle_user_id)
    end

    context "when the user has already been deleted (404)" do
      before do
        allow(argyle_service).to receive(:delete_user).and_raise(Faraday::ResourceNotFound.new(nil, nil))
      end

      it "does not raise an error" do
        expect { service.send(:delete_argyle_user, client_agency_id, argyle_user_id) }.not_to raise_error
      end

      it "logs an info message" do
        expect(Rails.logger).to receive(:info).with("Argyle User #{argyle_user_id} already deleted")
        service.send(:delete_argyle_user, client_agency_id, argyle_user_id)
      end
    end

    context "when deletion fails" do
      let(:error) { StandardError.new("API Error") }

      before do
        allow(argyle_service).to receive(:delete_user).and_raise(error)
      end

      context "in production" do
        before do
          allow(Rails.env).to receive(:production?).and_return(true)
        end

        it "logs the error" do
          expect(Rails.logger).to receive(:error).with("Unable to delete Argyle User #{argyle_user_id} - API Error")
          service.send(:delete_argyle_user, client_agency_id, argyle_user_id)
        end

        it "tracks the failure event" do
          tracker = instance_double(GenericEventTracker)
          allow(GenericEventTracker).to receive(:new).and_return(tracker)
          expect(tracker).to receive(:track).with("DataRedactionFailure", nil, { argyle_user_id: argyle_user_id })
          service.send(:delete_argyle_user, client_agency_id, argyle_user_id)
        end

        it "does not raise the error" do
          expect { service.send(:delete_argyle_user, client_agency_id, argyle_user_id) }.not_to raise_error
        end
      end

      context "in non-production" do
        before do
          allow(Rails.env).to receive(:production?).and_return(false)
        end

        it "raises the error" do
          expect { service.send(:delete_argyle_user, client_agency_id, argyle_user_id) }
            .to raise_error(StandardError, "API Error")
        end
      end
    end
  end

  describe ".manually_redact_by_partner_identifier!" do
    let(:cbv_flow_invitation) do
      create(:cbv_flow_invitation, client_agency_id: "sandbox",
        cbv_applicant_attributes: { client_agency_id: "sandbox", case_number: "DELETEME001" })
    end
    let!(:cbv_flow) { CbvFlow.create_from_invitation(cbv_flow_invitation, "test_device_id") }
    let!(:second_cbv_flow) { CbvFlow.create_from_invitation(cbv_flow_invitation, "test_device_id_2") }
    let!(:payroll_account) { create(:payroll_account, cbv_flow: second_cbv_flow) }

    it "redacts the invitation, all flow objects, and the metadata jsonb keys flagged redactable" do
      DataRetentionService.manually_redact_by_partner_identifier!("sandbox", "DELETEME001")

      expect(cbv_flow.reload).to have_attributes(
        redacted_at: within(1.second).of(Time.now)
      )

      applicant = cbv_flow.cbv_applicant.reload
      expect(applicant.redacted_at).to be_within(1.second).of(Time.now)

      expect(applicant.first_name).to eq("REDACTED")
      expect(applicant.agency_partner_metadata).to include("first_name" => "REDACTED")

      expect(applicant.partner_identifier).to eq("DELETEME001")

      expect(second_cbv_flow.reload).to have_attributes(
        redacted_at: within(1.second).of(Time.now)
      )
      expect(cbv_flow_invitation.reload).to have_attributes(
        redacted_at: within(1.second).of(Time.now)
      )
      expect(payroll_account.reload).to have_attributes(
        redacted_at: within(1.second).of(Time.now)
      )
    end

    it "redacts every matching applicant when the same partner_identifier value is reused within an agency" do
      duplicate_invitation = create(:cbv_flow_invitation, client_agency_id: "sandbox",
        cbv_applicant_attributes: { client_agency_id: "sandbox", case_number: "DELETEME001" })
      duplicate_flow = CbvFlow.create_from_invitation(duplicate_invitation, "another_device")

      DataRetentionService.manually_redact_by_partner_identifier!("sandbox", "DELETEME001")

      expect(duplicate_flow.reload.redacted_at).to be_within(1.second).of(Time.now)
      expect(duplicate_flow.cbv_applicant.reload.redacted_at).to be_within(1.second).of(Time.now)
    end

    it "does not touch applicants with the same partner_identifier in a different agency" do
      other_agency_invitation = create(:cbv_flow_invitation, :az_des,
        cbv_applicant_attributes: { client_agency_id: "az_des", case_number: "DELETEME001",
                                     first_name: "Other", last_name: "Person" })
      other_flow = CbvFlow.create_from_invitation(other_agency_invitation, "az_device")

      DataRetentionService.manually_redact_by_partner_identifier!("sandbox", "DELETEME001")

      expect(other_flow.reload.redacted_at).to be_nil
      expect(other_flow.cbv_applicant.reload.redacted_at).to be_nil
      expect(other_flow.cbv_applicant.partner_identifier).to eq("DELETEME001")
    end

    it "raises when no applicant matches" do
      expect {
        DataRetentionService.manually_redact_by_partner_identifier!("sandbox", "DOES_NOT_EXIST")
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    context "when the agency's partner_identifier_name attribute is also flagged redactable" do
      before do
        sandbox_config = PartnerConfig.find_by(partner_id: "sandbox")
        PartnerApplicationAttribute
          .where(partner_config: sandbox_config, name: "case_number")
          .update_all(redactable: true, redact_type: "string")
        ClientAgencyConfig.reset!
      end

      it "redacts the partner_identifier column" do
        DataRetentionService.manually_redact_by_partner_identifier!("sandbox", "DELETEME001")

        expect(cbv_flow.cbv_applicant.reload.partner_identifier).to eq("REDACTED")
      end
    end

    context "when a flow has an argyle_user_id" do
      before do
        second_cbv_flow.update!(argyle_user_id: "argyle_manual_123", client_agency_id: "sandbox")
      end

      it "deletes the argyle user" do
        expect_any_instance_of(DataRetentionService).to receive(:delete_argyle_user).with("sandbox", "argyle_manual_123")
        DataRetentionService.manually_redact_by_partner_identifier!("sandbox", "DELETEME001")
      end
    end
  end

  describe "#redact_cbv_flow" do
    let(:cbv_flow) { create(:cbv_flow, argyle_user_id: "argyle_123", client_agency_id: "sandbox") }
    let(:service) { DataRetentionService.new }

    it "deletes the argyle user when argyle_user_id is present" do
      expect(service).to receive(:delete_argyle_user).with(cbv_flow.client_agency_id, cbv_flow.argyle_user_id)
      service.send(:redact_cbv_flow, cbv_flow)
    end

    it "does not attempt to delete argyle user when argyle_user_id is nil" do
      cbv_flow.update(argyle_user_id: nil)
      expect(service).not_to receive(:delete_argyle_user)
      service.send(:redact_cbv_flow, cbv_flow)
    end

    it "calls delete_argyle_user before redacting local records" do
      expect(service).to receive(:delete_argyle_user).ordered
      expect(cbv_flow).to receive(:redact!).ordered
      service.send(:redact_cbv_flow, cbv_flow)
    end

    context "when delete_argyle_user raises an error" do
      before do
        allow(service).to receive(:delete_argyle_user).and_raise(StandardError.new("API Error"))
      end

      it "does not redact local records" do
        expect { service.send(:redact_cbv_flow, cbv_flow) }.to raise_error(StandardError)
        expect(cbv_flow.reload.redacted_at).to be_nil
      end
    end
  end
end
