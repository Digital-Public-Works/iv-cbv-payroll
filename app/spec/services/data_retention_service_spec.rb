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

    # Invitations redact on the next daily run after expires_at -- no grace.
    # The implicit ≤24h tolerance (between expiry and the next scheduled task
    # firing) is documented in partner data-sharing agreements.
    context "for an unused invitation (no associated CbvFlow)" do
      context "before the invitation expires" do
        let(:now) { cbv_flow_invitation.expires_at - 1.minute }

        it "does not redact the invitation" do
          expect { service.redact_invitations }
            .not_to change { cbv_flow_invitation.reload.attributes }
        end
      end

      context "after the invitation has expired" do
        let(:now) { cbv_flow_invitation.expires_at + 1.minute }

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

        context "when one invitation's applicant redaction raises" do
          let!(:other_invitation) { create(:cbv_flow_invitation, :sandbox) }

          before do
            allow(Rails.env).to receive(:production?).and_return(true)

            # `now` is already past the first invitation's expiry, but
            # other_invitation is created at that advanced clock, so back-date
            # its expires_at explicitly to bring it past expiry too.
            other_invitation.update!(expires_at: now - 1.day)

            allow_any_instance_of(CbvApplicant).to receive(:redact!).and_wrap_original do |original, *args|
              if original.receiver.id == cbv_flow_invitation.cbv_applicant.id
                raise RuntimeError, "No fields to redact for #{original.receiver.client_agency_id}"
              else
                original.call(*args)
              end
            end
          end

          it "still redacts the other invitation" do
            expect { service.redact_invitations }.not_to raise_error
            expect(other_invitation.reload.redacted_at).to be_within(1.second).of(Time.now)
          end

          it "tracks a DataRedactionFailure event for the failing invitation" do
            tracker = instance_double(GenericEventTracker)
            allow(GenericEventTracker).to receive(:new).and_return(tracker)
            expect(tracker).to receive(:track).with(
              "DataRedactionFailure",
              nil,
              hash_including(
                cbv_flow_invitation_id: cbv_flow_invitation.id,
                client_agency_id: cbv_flow_invitation.client_agency_id
              )
            )
            service.redact_invitations
          end
        end
      end
    end
  end

  describe "#redact_cbv_flows" do
    let!(:cbv_flow_invitation) do
      create(:cbv_flow_invitation)
    end
    let!(:cbv_flow) { CbvFlow.create_from_invitation(cbv_flow_invitation, "test_device_id") }
    let(:service) { DataRetentionService.new }
    let(:deletion_threshold) { cbv_flow.created_at + DataRetentionService::REDACT_CBV_FLOWS_AFTER }
    let(:now) { Time.now }

    around do |ex|
      Timecop.freeze(now, &ex)
    end

    context "before the deletion threshold" do
      let(:now) { deletion_threshold - 1.minute }

      it "does not redact the CbvFlow" do
        expect { service.redact_cbv_flows }
          .not_to change { cbv_flow.reload.attributes }
      end

      it "does not redact the CbvFlowInvitation" do
        expect { service.redact_cbv_flows }
          .not_to change { cbv_flow_invitation.reload.attributes }
      end

      it "does not redact the CbvApplicant" do
        expect { service.redact_cbv_flows }
          .not_to change { cbv_flow.cbv_applicant.reload.attributes }
      end

      it "does not redact an associated PayrollAccount" do
        payroll_account = create(:payroll_account, cbv_flow: cbv_flow)

        expect { service.redact_cbv_flows }
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

      it "redacts the CbvFlow" do
        service.redact_cbv_flows
        expect(cbv_flow.reload).to have_attributes(
          end_user_id: "00000000-0000-0000-0000-000000000000",
          additional_information: {}
        )
      end

      it "redacts the associated invitation" do
        service.redact_cbv_flows
        expect(cbv_flow_invitation.reload).to have_attributes(
          auth_token: "REDACTED",
          redacted_at: within(1.second).of(now)
        )
      end

      it "redacts the associated CbvApplicant" do
        service.redact_cbv_flows
        expect(cbv_flow.cbv_applicant.reload).to have_attributes(
          first_name: "REDACTED"
        )
      end

      it "redacts an associated PayrollAccount" do
        payroll_account = create(:payroll_account, cbv_flow: cbv_flow)
        service.redact_cbv_flows
        expect(payroll_account.reload).to have_attributes(
          redacted_at: within(1.second).of(now)
        )
      end

      it "skips redacting already-redacted CbvFlows" do
        service.redact_cbv_flows

        expect_any_instance_of(CbvFlow).not_to receive(:redact!)
        service.redact_cbv_flows
      end

      # Uniform 7-day rule applies regardless of completion / transmission state.
      context "for a complete CbvFlow (confirmation_code present)" do
        before do
          cbv_flow.update(confirmation_code: "SANDBOX001")
        end

        it "still redacts the CbvFlow" do
          service.redact_cbv_flows
          expect(cbv_flow.reload.redacted_at).to be_within(1.second).of(now)
        end

        it "still redacts the invitation" do
          service.redact_cbv_flows
          expect(cbv_flow_invitation.reload.redacted_at).to be_within(1.second).of(now)
        end
      end

      context "for a transmitted CbvFlow (transmitted_at present)" do
        before do
          cbv_flow.update(confirmation_code: "SANDBOX001", transmitted_at: now - 1.day)
        end

        it "still redacts the CbvFlow" do
          service.redact_cbv_flows
          expect(cbv_flow.reload.redacted_at).to be_within(1.second).of(now)
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
          service.redact_cbv_flows
        end
      end

      context "when the cbv_flow has no argyle_user_id" do
        before do
          cbv_flow.update(argyle_user_id: nil)
        end

        it "does not attempt to delete argyle user" do
          expect(service).not_to receive(:delete_argyle_user)
          service.redact_cbv_flows
        end
      end
    end

    # Standalone flow (no invitation): uniform 7-day rule from cbv_flow.created_at
    # applies the same way -- no longer keyed off updated_at.
    context "when the CbvFlow has no invitation" do
      let(:cbv_flow) { create(:cbv_flow, :invited, cbv_flow_invitation: nil) }
      let(:deletion_threshold) { cbv_flow.created_at + DataRetentionService::REDACT_CBV_FLOWS_AFTER }

      context "before the deletion threshold" do
        let(:now) { deletion_threshold - 1.minute }

        it "does not redact the CbvFlow" do
          expect { service.redact_cbv_flows }
            .not_to change { cbv_flow.reload.attributes }
        end
      end

      context "after the deletion threshold" do
        let(:now) { deletion_threshold + 1.minute }

        it "redacts the CbvFlow" do
          service.redact_cbv_flows
          expect(cbv_flow.reload).to have_attributes(
            end_user_id: "00000000-0000-0000-0000-000000000000",
            additional_information: {}
          )
        end

        it "redacts an associated PayrollAccount" do
          payroll_account = create(:payroll_account, cbv_flow: cbv_flow)
          service.redact_cbv_flows
          expect(payroll_account.reload).to have_attributes(
            redacted_at: within(1.second).of(now)
          )
        end
      end
    end
  end

  describe "#redact_backstop!" do
    let(:service) { DataRetentionService.new }
    let(:now) { Time.now }
    let(:event_logger) { instance_double(GenericEventTracker, track: nil) }

    around do |ex|
      Timecop.freeze(now, &ex)
    end

    before do
      allow(GenericEventTracker).to receive(:new).and_return(event_logger)
    end

    context "CbvFlow rows older than REDACT_BACKSTOP" do
      let!(:cbv_flow_invitation) { create(:cbv_flow_invitation) }
      let!(:cbv_flow) do
        CbvFlow.create_from_invitation(cbv_flow_invitation, "test_device_id").tap do |f|
          f.update_columns(created_at: now - DataRetentionService::REDACT_BACKSTOP - 1.day)
        end
      end

      it "redacts the CbvFlow even when caught by the backstop" do
        service.redact_backstop!
        expect(cbv_flow.reload.redacted_at).to be_within(1.second).of(now)
      end

      it "redacts the associated invitation" do
        service.redact_backstop!
        expect(cbv_flow_invitation.reload.redacted_at).to be_within(1.second).of(now)
      end

      it "emits a backstop-hit warning to the Rails logger" do
        expect(Rails.logger).to receive(:warn).with(/DataRetention backstop hit: CbvFlow/)
        service.redact_backstop!
      end

      it "emits a backstop-hit error to NewRelic" do
        expect(NewRelic::Agent).to receive(:notice_error)
          .with(kind_of(StandardError), hash_including(custom_params: hash_including(model: "CbvFlow", cbv_flow_id: cbv_flow.id)))
        service.redact_backstop!
      end

      it "emits a DataRedactionBackstopHit event for the Mixpanel/analytics channel" do
        expect(event_logger).to receive(:track)
          .with("DataRedactionBackstopHit", nil, hash_including(model: "CbvFlow", cbv_flow_id: cbv_flow.id))
        service.redact_backstop!
      end
    end

    context "CbvFlow rows younger than REDACT_BACKSTOP" do
      let!(:cbv_flow_invitation) { create(:cbv_flow_invitation) }
      let!(:cbv_flow) { CbvFlow.create_from_invitation(cbv_flow_invitation, "test_device_id") }

      it "does not redact the flow" do
        expect { service.redact_backstop! }.not_to change { cbv_flow.reload.attributes }
      end

      it "does not emit a backstop-hit warning for this CbvFlow" do
        # Allow any other warnings from pre-existing test-DB state; assert only
        # that THIS record under test does not trigger a warning.
        allow(Rails.logger).to receive(:warn)
        expect(Rails.logger).not_to receive(:warn).with(/cbv_flow_id: #{cbv_flow.id}\b/)
        service.redact_backstop!
      end
    end

    # Invitations are NOT in the backstop -- they have variable lifetime up
    # to 366 days. Assert that the backstop does not redact an aged-but-still-
    # valid (or aged-but-unredacted) invitation, even with associated unredacted
    # records past 15 days.
    context "old unredacted CbvFlowInvitation (NOT in backstop)" do
      let!(:cbv_flow_invitation) do
        create(:cbv_flow_invitation, :sandbox).tap do |inv|
          inv.update_columns(created_at: now - DataRetentionService::REDACT_BACKSTOP - 1.day)
        end
      end

      it "does not redact the invitation via the backstop" do
        expect { service.redact_backstop! }
          .not_to change { cbv_flow_invitation.reload.redacted_at }
      end

      it "does not emit a backstop-hit warning for the invitation" do
        allow(Rails.logger).to receive(:warn)
        expect(Rails.logger).not_to receive(:warn).with(/cbv_flow_invitation_id: #{cbv_flow_invitation.id}\b/)
        service.redact_backstop!
      end
    end

    # CbvApplicant backstop catches only true cascade-misses: applicants
    # whose associations are all redacted (or absent). An applicant tied to
    # an unredacted invitation is NOT caught -- that invitation's own
    # lifecycle drives the redaction.
    context "CbvApplicant with no associations (true orphan)" do
      let!(:applicant) do
        create(:cbv_applicant, client_agency_id: "sandbox").tap do |a|
          a.update_columns(created_at: now - DataRetentionService::REDACT_BACKSTOP - 1.day)
        end
      end

      it "redacts the orphan applicant" do
        service.redact_backstop!
        expect(applicant.reload.redacted_at).to be_within(1.second).of(now)
      end

      it "emits a backstop-hit warning identifying CbvApplicant" do
        expect(Rails.logger).to receive(:warn).with(/DataRetention backstop hit: CbvApplicant/)
        service.redact_backstop!
      end

      it "emits a DataRedactionBackstopHit event for the applicant" do
        expect(event_logger).to receive(:track)
          .with("DataRedactionBackstopHit", nil, hash_including(model: "CbvApplicant", cbv_applicant_id: applicant.id))
        service.redact_backstop!
      end
    end

    context "CbvApplicant tied to an unredacted invitation (NOT a cascade miss)" do
      let!(:cbv_flow_invitation) { create(:cbv_flow_invitation, :sandbox) }
      let!(:applicant) do
        cbv_flow_invitation.cbv_applicant.tap do |a|
          a.update_columns(created_at: now - DataRetentionService::REDACT_BACKSTOP - 1.day)
        end
      end

      it "does not redact the applicant" do
        expect { service.redact_backstop! }.not_to change { applicant.reload.redacted_at }
      end

      it "does not emit a backstop-hit warning for the applicant" do
        allow(Rails.logger).to receive(:warn)
        expect(Rails.logger).not_to receive(:warn).with(/cbv_applicant_id: #{applicant.id}\b/)
        service.redact_backstop!
      end
    end

    context "CbvApplicant whose associations have all been redacted (cascade miss)" do
      let!(:cbv_flow_invitation) do
        create(:cbv_flow_invitation, :sandbox).tap do |inv|
          inv.update_columns(redacted_at: now - 1.day)
        end
      end
      let!(:applicant) do
        cbv_flow_invitation.cbv_applicant.tap do |a|
          a.update_columns(created_at: now - DataRetentionService::REDACT_BACKSTOP - 1.day)
        end
      end

      it "redacts the cascade-missed applicant" do
        service.redact_backstop!
        expect(applicant.reload.redacted_at).to be_within(1.second).of(now)
      end

      it "emits a backstop-hit warning identifying CbvApplicant" do
        expect(Rails.logger).to receive(:warn).with(/DataRetention backstop hit: CbvApplicant.*cbv_applicant_id: #{applicant.id}/)
        service.redact_backstop!
      end
    end

    context "already-redacted records" do
      let!(:cbv_flow) do
        create(:cbv_flow).tap do |f|
          f.cbv_applicant.update_columns(redacted_at: now - 2.days)
          f.update_columns(created_at: now - DataRetentionService::REDACT_BACKSTOP - 1.day, redacted_at: now - 2.days)
        end
      end

      it "does not re-process already-redacted CbvFlows" do
        expect_any_instance_of(CbvFlow).not_to receive(:redact!)
        service.redact_backstop!
      end

      it "does not emit a backstop-hit warning for this already-redacted CbvFlow" do
        # Allow any other warnings from pre-existing test-DB state; assert only
        # that this redacted record does not trigger a warning.
        allow(Rails.logger).to receive(:warn)
        expect(Rails.logger).not_to receive(:warn).with(/cbv_flow_id: #{cbv_flow.id}\b/)
        service.redact_backstop!
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
      expect(applicant.custom_attributes).to include("first_name" => "REDACTED")

      # partner_identifier is always redacted, even though sandbox's case_number
      # is not configured as a redactable attribute.
      expect(applicant.partner_identifier).to eq("REDACTED")

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

    context "when local redaction raises (e.g. no redactable fields configured)" do
      before do
        allow(cbv_flow).to receive(:redact!)
          .and_raise(RuntimeError.new("No fields to redact for #{cbv_flow.client_agency_id}"))
      end

      context "in production" do
        before do
          allow(Rails.env).to receive(:production?).and_return(true)
        end

        it "still calls delete_argyle_user" do
          expect(service).to receive(:delete_argyle_user).with(cbv_flow.client_agency_id, cbv_flow.argyle_user_id)
          service.send(:redact_cbv_flow, cbv_flow)
        end

        it "calls delete_argyle_user before the local redaction raises" do
          allow(service).to receive(:delete_argyle_user).ordered
          expect(service).to receive(:delete_argyle_user).ordered
          expect(cbv_flow).to receive(:redact!).ordered
            .and_raise(RuntimeError.new("No fields to redact for #{cbv_flow.client_agency_id}"))
          service.send(:redact_cbv_flow, cbv_flow)
        end

        it "does not propagate the error" do
          allow(service).to receive(:delete_argyle_user)
          expect { service.send(:redact_cbv_flow, cbv_flow) }.not_to raise_error
        end

        it "tracks a DataRedactionFailure event with the cbv_flow context" do
          allow(service).to receive(:delete_argyle_user)
          tracker = instance_double(GenericEventTracker)
          allow(GenericEventTracker).to receive(:new).and_return(tracker)
          expect(tracker).to receive(:track).with(
            "DataRedactionFailure",
            nil,
            hash_including(cbv_flow_id: cbv_flow.id, client_agency_id: cbv_flow.client_agency_id)
          )
          service.send(:redact_cbv_flow, cbv_flow)
        end

        it "notifies NewRelic of the error so it shows up in the Errors dashboard" do
          allow(service).to receive(:delete_argyle_user)
          expect(NewRelic::Agent).to receive(:notice_error).with(
            kind_of(RuntimeError),
            custom_params: hash_including(cbv_flow_id: cbv_flow.id, client_agency_id: cbv_flow.client_agency_id)
          )
          service.send(:redact_cbv_flow, cbv_flow)
        end

        it "writes a log line so the error reaches CloudWatch and forwarded NewRelic logs" do
          allow(service).to receive(:delete_argyle_user)
          expect(Rails.logger).to receive(:error).with(/Data redaction failed.*No fields to redact/)
          service.send(:redact_cbv_flow, cbv_flow)
        end
      end

      context "in non-production" do
        before do
          allow(Rails.env).to receive(:production?).and_return(false)
        end

        it "still calls delete_argyle_user before the raise propagates" do
          expect(service).to receive(:delete_argyle_user).with(cbv_flow.client_agency_id, cbv_flow.argyle_user_id)
          expect { service.send(:redact_cbv_flow, cbv_flow) }.to raise_error(RuntimeError, /No fields to redact/)
        end
      end
    end

    context "when a dependent redaction raises mid-sequence (retry safety)" do
      before do
        allow(service).to receive(:delete_argyle_user)
        allow(Rails.env).to receive(:production?).and_return(true)
        # A dependent record fails to redact. The CbvFlow itself must be redacted
        # LAST so that, on failure, it remains unredacted and gets retried on the
        # next run instead of being marked done with partially-redacted children.
        allow_any_instance_of(CbvApplicant).to receive(:redact!)
          .and_raise(RuntimeError.new("Simulated applicant redaction failure"))
      end

      it "leaves the cbv_flow unredacted so the next run re-selects and retries it" do
        service.send(:redact_cbv_flow, cbv_flow)
        expect(cbv_flow.reload.redacted_at).to be_nil
      end

      it "reports the failure rather than swallowing it silently" do
        expect(service).to receive(:report_redaction_failure)
          .with(kind_of(RuntimeError), hash_including(cbv_flow_id: cbv_flow.id))
        service.send(:redact_cbv_flow, cbv_flow)
      end
    end

    context "for a pa_dhs flow whose applicant has only a non-redactable case_number" do
      # Build the applicant directly (not via the :pa_dhs factory trait, which
      # sets name attributes) so that custom_attributes stays empty — mirroring
      # the production pa_dhs shape from the 2026-04-10 incident. That is the
      # exact condition that tripped the removed guard in CbvApplicant#redact!
      # (blank redactable fields + non-redactable partner_identifier + blank
      # custom_attributes), so this fails against the old code and passes now.
      let(:cbv_applicant) do
        CbvApplicant.create!(
          client_agency_id: "pa_dhs",
          case_number: "PA-CASE-123",
          snap_application_date: Date.current,
          income_changes: [ { "change_type" => "Start", "member_name" => "Pat Penn" } ]
        )
      end
      let(:cbv_flow_invitation) { create(:cbv_flow_invitation, :pa_dhs, cbv_applicant: cbv_applicant) }
      let(:cbv_flow) do
        CbvFlow.create_from_invitation(cbv_flow_invitation, "device_pa").tap do |f|
          f.update!(argyle_user_id: "argyle_PA_1")
        end
      end
      let(:fake_argyle) { instance_double(Aggregators::Sdk::ArgyleService) }

      before do
        # The shared test harness seeds every partner (including pa_dhs) with
        # redactable name/dob fields, which hides the original bug. Strip pa_dhs
        # down to its production shape: a single required, non-redactable
        # case_number (also the partner_identifier). Transactional fixtures roll
        # this back and `before(:each)` rebuilds ClientAgencyConfig, so the
        # mutation is scoped to this context.
        pa_dhs_config = PartnerConfig.find_by(partner_id: "pa_dhs")
        PartnerApplicationAttribute
          .where(partner_config: pa_dhs_config)
          .where.not(name: %w[case_number income_changes])
          .delete_all
        PartnerApplicationAttribute
          .where(partner_config: pa_dhs_config, name: "case_number")
          .update_all(required: true, redactable: false, redact_type: nil)
        ClientAgencyConfig.reset!

        argyle_environment = ClientAgencyConfig.instance["pa_dhs"].argyle_environment
        allow(Aggregators::Sdk::ArgyleService).to receive(:new).with(argyle_environment).and_return(fake_argyle)
        allow(fake_argyle).to receive(:delete_user)
      end

      it "completes without raising (regression test for the 2026-04-10 step function failure)" do
        expect { service.send(:redact_cbv_flow, cbv_flow) }.not_to raise_error
      end

      it "marks the cbv_flow as redacted" do
        service.send(:redact_cbv_flow, cbv_flow)
        expect(cbv_flow.reload.redacted_at).to be_within(1.second).of(Time.now)
      end

      it "marks the cbv_applicant as redacted" do
        service.send(:redact_cbv_flow, cbv_flow)
        expect(cbv_flow.cbv_applicant.reload.redacted_at).to be_within(1.second).of(Time.now)
      end

      it "redacts the partner_identifier (case_number) even though it has no configured redactable fields" do
        expect(cbv_flow.cbv_applicant.partner_identifier).to be_present
        service.send(:redact_cbv_flow, cbv_flow)
        expect(cbv_flow.cbv_applicant.reload.partner_identifier).to eq("REDACTED")
      end

      it "still deletes the argyle user" do
        expect(fake_argyle).to receive(:delete_user).with(argyle_user_id: "argyle_PA_1")
        service.send(:redact_cbv_flow, cbv_flow)
      end
    end
  end

  describe "iteration resilience: one bad record never poisons the rest of the batch" do
    let(:service) { DataRetentionService.new }
    let(:fake_argyle) { instance_double(Aggregators::Sdk::ArgyleService) }
    let(:now) { Time.now }

    around do |ex|
      Timecop.freeze(now, &ex)
    end

    before do
      allow(Rails.env).to receive(:production?).and_return(true)
      argyle_environment = ClientAgencyConfig.instance["sandbox"].argyle_environment
      allow(Aggregators::Sdk::ArgyleService).to receive(:new).with(argyle_environment).and_return(fake_argyle)
      allow(fake_argyle).to receive(:delete_user)
    end

    # Build a "good" and a "bad" flow. The uniform redaction rule keys off
    # cbv_flow.created_at, so callers pass a backdated created_at to push the
    # flow past whichever threshold they're exercising (primary or backstop).
    def make_two_flows(transmitted_at: nil, created_at: nil)
      %w[good bad].map do |suffix|
        invitation = create(:cbv_flow_invitation)
        flow = CbvFlow.create_from_invitation(invitation, "device_#{suffix}")
        updates = { argyle_user_id: "argyle_#{suffix.upcase}" }
        updates[:transmitted_at] = transmitted_at if transmitted_at
        flow.update!(updates)
        # `created_at` is normally Rails-managed; bypass via update_columns
        # so factories can age the flow without tripping callbacks/validations.
        flow.update_columns(created_at: created_at) if created_at
        flow.reload
      end
    end

    def raise_on_one_applicant(bad_flow)
      allow_any_instance_of(CbvApplicant).to receive(:redact!).and_wrap_original do |original, *args|
        if original.receiver.id == bad_flow.cbv_applicant.id
          raise RuntimeError, "Simulated redaction failure for #{original.receiver.client_agency_id}"
        else
          original.call(*args)
        end
      end
    end

    context "#redact_cbv_flows (primary)" do
      # Age the flows past the primary 7-day rule by backdating created_at.
      let(:created_at) { now - DataRetentionService::REDACT_CBV_FLOWS_AFTER - 1.day }
      let!(:flows) { make_two_flows(created_at: created_at) }
      let(:good_flow) { flows.first }
      let(:bad_flow) { flows.last }

      before { raise_on_one_applicant(bad_flow) }

      it "still calls delete_user for both flows" do
        expect(fake_argyle).to receive(:delete_user).with(argyle_user_id: "argyle_GOOD")
        expect(fake_argyle).to receive(:delete_user).with(argyle_user_id: "argyle_BAD")
        expect { service.redact_cbv_flows }.not_to raise_error
      end

      it "still redacts the good flow" do
        service.redact_cbv_flows
        expect(good_flow.reload.redacted_at).to be_within(1.second).of(now)
      end

      it "reports the failing flow to NewRelic" do
        expect(NewRelic::Agent).to receive(:notice_error)
          .with(kind_of(RuntimeError), custom_params: hash_including(cbv_flow_id: bad_flow.id))
        service.redact_cbv_flows
      end
    end

    context "#redact_backstop!" do
      let(:created_at) { now - DataRetentionService::REDACT_BACKSTOP - 1.day }
      let!(:flows) { make_two_flows(created_at: created_at) }
      let(:good_flow) { flows.first }
      let(:bad_flow) { flows.last }

      before { raise_on_one_applicant(bad_flow) }

      it "still calls delete_user for both flows" do
        expect(fake_argyle).to receive(:delete_user).with(argyle_user_id: "argyle_GOOD")
        expect(fake_argyle).to receive(:delete_user).with(argyle_user_id: "argyle_BAD")
        expect { service.redact_backstop! }.not_to raise_error
      end

      it "still redacts the good flow" do
        service.redact_backstop!
        expect(good_flow.reload.redacted_at).to be_within(1.second).of(now)
      end
    end

    context "#redact_invitations" do
      let!(:good_invitation) { create(:cbv_flow_invitation, :sandbox) }
      let!(:bad_invitation) { create(:cbv_flow_invitation, :sandbox) }

      before do
        [ good_invitation, bad_invitation ].each do |inv|
          inv.update!(expires_at: now - 1.day)
        end

        allow_any_instance_of(CbvApplicant).to receive(:redact!).and_wrap_original do |original, *args|
          if original.receiver.id == bad_invitation.cbv_applicant.id
            raise RuntimeError, "Simulated redaction failure"
          else
            original.call(*args)
          end
        end
      end

      it "still redacts the good invitation when the bad one raises" do
        expect { service.redact_invitations }.not_to raise_error
        expect(good_invitation.reload.redacted_at).to be_within(1.second).of(now)
      end

      it "reports the failing invitation to NewRelic" do
        expect(NewRelic::Agent).to receive(:notice_error)
          .with(kind_of(RuntimeError), custom_params: hash_including(cbv_flow_invitation_id: bad_invitation.id))
        service.redact_invitations
      end
    end
  end

  describe ".redact_all! end-to-end" do
    let(:service) { DataRetentionService.new }
    let(:now) { Time.now }
    let(:fake_argyle) { instance_double(Aggregators::Sdk::ArgyleService) }

    around do |ex|
      Timecop.freeze(now, &ex)
    end

    before do
      ClientAgencyConfig.instance.client_agency_ids.each do |agency_id|
        argyle_environment = ClientAgencyConfig.instance[agency_id].argyle_environment
        allow(Aggregators::Sdk::ArgyleService).to receive(:new).with(argyle_environment).and_return(fake_argyle)
      end
      allow(fake_argyle).to receive(:delete_user)
    end

    # Smoke test that redaction completes end-to-end for every agency. The
    # az_des and pa_dhs applicant factory traits null out first_name/last_name,
    # which the test harness marks required, so supply them here.
    # Uniform-7-day rule keys off cbv_flow.created_at; age the flow there.
    %i[sandbox az_des la_ldh pa_dhs].each do |agency|
      it "redacts a transmitted #{agency} flow without raising" do
        invitation = create(:cbv_flow_invitation, agency,
          cbv_applicant_attributes: { first_name: "Test", last_name: "Person" })
        flow = CbvFlow.create_from_invitation(invitation, "device_#{agency}")
        flow.update!(
          argyle_user_id: "argyle_#{agency}",
          confirmation_code: "OKAY#{agency.upcase}",
          transmitted_at: now - 1.day
        )
        flow.update_columns(created_at: now - DataRetentionService::REDACT_CBV_FLOWS_AFTER - 1.day)

        expect { service.redact_all! }.not_to raise_error

        expect(flow.reload.redacted_at).to be_within(1.second).of(now)
        expect(flow.cbv_applicant.reload.redacted_at).to be_within(1.second).of(now)
      end
    end
  end
end
