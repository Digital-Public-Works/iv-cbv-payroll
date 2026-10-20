require "rails_helper"

RSpec.describe DeferredReportValidator do
  let(:event_logger) { instance_double(GenericEventTracker, track: nil) }
  let(:cbv_flow) { create(:cbv_flow, :generic, :with_argyle_account) }
  let(:payroll_account) { cbv_flow.payroll_accounts.first }
  let(:validator) { described_class.new(cbv_flow, event_logger: event_logger) }

  let(:account_report_service) do
    instance_double(Aggregators::AccountReportService, validate: validation_result)
  end

  let(:validation_result) do
    instance_double(
      Aggregators::AccountReportService::ValidationResult,
      valid?: valid,
      error_messages: "No identities present"
    )
  end

  before do
    # The sync is over and succeeded; only the report verdict was deferred,
    # which is the state the webhook leaves it in when the partner still has
    # applicant information to collect.
    payroll_account.update!(synchronization_status: :succeeded, report_status: :unknown)

    allow(validator).to receive(:set_aggregator_report_for_account)
    allow(Aggregators::AccountReportService).to receive(:new).and_return(account_report_service)
  end

  context "when the report is useful" do
    let(:valid) { true }

    it "marks the report useful" do
      expect { validator.run }
        .to change { payroll_account.reload.report_status }.to("useful")
    end

    it "leaves the sync status alone" do
      expect { validator.run }.not_to change { payroll_account.reload.synchronization_status }
    end

    it "reports the account as valid" do
      result = validator.run

      expect(result.valid_accounts).to eq([ payroll_account ])
      expect(result.first_invalid_account).to be_nil
    end

    it "tracks the met-requirements event" do
      validator.run

      expect(event_logger).to have_received(:track)
        .with(TrackEvent::ApplicantReportMetUsefulRequirements, nil, hash_including(deferred: true))
    end
  end

  context "when the report is not useful" do
    let(:valid) { false }

    it "marks the report not useful without failing the sync" do
      expect { validator.run }
        .to change { payroll_account.reload.report_status }.to("not_useful")

      expect(payroll_account.reload).to be_sync_succeeded
    end

    it "hands back the account to send the applicant to the validation failure page" do
      expect(validator.run.first_invalid_account).to eq(payroll_account)
    end

    it "tracks the failed-requirements event with the errors" do
      validator.run

      expect(event_logger).to have_received(:track).with(
        TrackEvent::ApplicantReportFailedUsefulRequirements,
        nil,
        hash_including(deferred: true, errors: "No identities present")
      )
    end
  end

  context "when an account's report has already been judged" do
    let(:valid) { true }

    before { payroll_account.update!(report_status: :not_useful) }

    it "leaves it alone" do
      expect(validator.run.valid_accounts).to be_empty
      expect(payroll_account.reload.report_status).to eq("not_useful")
    end
  end

  context "when building the report blows up" do
    let(:valid) { true }

    before do
      allow(validator).to receive(:set_aggregator_report_for_account).and_raise(StandardError, "argyle is down")
    end

    it "marks the report unusable rather than leaving the applicant stranded" do
      expect { validator.run }
        .to change { payroll_account.reload.report_status }.to("not_useful")
    end
  end
end
