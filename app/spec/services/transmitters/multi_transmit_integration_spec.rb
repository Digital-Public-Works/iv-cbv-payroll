require "rails_helper"

RSpec.describe "Multi-transmission delivery", integration: true do
  let(:cbv_applicant) do
    create(:cbv_applicant,
      case_number: "MULTI001",
      agency_id_number: "AGN002",
      beacon_id: "BCN002",
      snap_application_date: Date.new(2025, 1, 15),
      first_name: "John",
      last_name: "Smith"
    )
  end

  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_argyle_account,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: Time.current,
      confirmation_code: "MULTI001",
      client_agency_id: "sandbox"
    )
  end

  let(:argyle_report) { build(:argyle_report, :with_argyle_account) }

  let(:webhook_config) do
    { "webhook_url" => "http://localhost:9292/api/v1/income-report", "api_key" => "my-secure-guid" }
  end

  let(:sftp_config) do
    {
      "user" => "testuser",
      "password" => sftp_password,
      "url" => "localhost",
      "port" => "2222",
      "sftp_directory" => "upload"
    }
  end

  let(:sftp_password) { "testpass" }

  let(:mock_client_agency) do
    instance_double(ClientAgencyConfig::ClientAgency,
      id: "sandbox",
      logo_path: "",
      timezone: "America/New_York",
      report_customization_show_earnings_list: true,
      transmission_methods: [
        ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(
          method: "webhook",
          configuration: webhook_config.with_indifferent_access
        ),
        ClientAgencyConfig::ClientAgency::TransmissionMethodEntry.new(
          method: "sftp",
          configuration: sftp_config.with_indifferent_access
        )
      ]
    )
  end

  # Force creation up-front with the real "sandbox" agency so CbvApplicant /
  # CbvFlowInvitation can read the real applicant_attributes / invitation_valid_days
  # during model initialization. The stubs below take over once the job runs.
  let!(:created_cbv_flow) { cbv_flow }

  before do
    allow(Aggregators::AggregatorReports::ArgyleReport).to receive(:new).and_return(argyle_report)
    allow_any_instance_of(CbvFlowTransmissionJob).to receive(:set_aggregator_report).and_return(argyle_report)
    allow_any_instance_of(CbvFlowTransmissionJob).to receive(:event_logger).and_return(instance_double(GenericEventTracker, track: nil))
    allow(mock_client_agency).to receive(:applicant_attributes).and_return({})

    allow(ClientAgencyConfig.instance).to receive(:[]).and_call_original
    allow(ClientAgencyConfig.instance).to receive(:[]).with("sandbox").and_return(mock_client_agency)

    # Stub PDF generation — we're testing transmission, not PDF rendering
    allow_any_instance_of(PdfService).to receive(:generate)
      .and_return(OpenStruct.new(content: "fake-pdf-content"))

    allow(mock_client_agency).to receive(:pdf_filename).and_return("IncomeReport_#{cbv_flow.confirmation_code}")

    # Use password-only SSH auth so Net::SSH does not scan local keys.
    allow(Net::SSH).to receive(:start).and_wrap_original do |original, host, user, **opts|
      original.call(host, user, **opts.merge(
        verify_host_key: :never,
        keys: [],
        auth_methods: %w[password]
      ))
    end

    WebMock.allow_net_connect!
  end

  after do
    WebMock.disable_net_connect!
  end

  context "when both methods succeed" do
    it "persists a succeeded CbvFlowTransmission per method and sets cbv_flow.transmitted_at" do
      expect { CaseWorkerTransmitterJob.new.perform(cbv_flow.id) }.not_to raise_error

      transmissions = cbv_flow.reload.cbv_flow_transmissions

      expect(transmissions.pluck(:method_type)).to contain_exactly("webhook", "sftp")
      expect(transmissions.all?(&:succeeded?)).to be(true), "all transmissions should succeed; got: #{transmissions.map(&:status)}"
      expect(transmissions.all? { |t| t.succeeded_at.present? }).to be(true)
      expect(cbv_flow.transmitted_at).to be_present
      # cbv_flow.transmitted_at is the time of the first successful transmission
      earliest_success = transmissions.map(&:succeeded_at).min
      expect(cbv_flow.transmitted_at).to be_within(1.second).of(earliest_success)
    end
  end

  context "when SFTP fails (wrong password) but webhook succeeds" do
    let(:sftp_password) { "wrong-password-on-purpose" }

    it "still marks the cbv_flow transmitted using the webhook's timestamp" do
      expect { CaseWorkerTransmitterJob.new.perform(cbv_flow.id) }.not_to raise_error

      cbv_flow.reload
      webhook = cbv_flow.cbv_flow_transmissions.find_by!(method_type: :webhook)
      sftp = cbv_flow.cbv_flow_transmissions.find_by!(method_type: :sftp)

      expect(webhook.succeeded?).to be(true)
      expect(webhook.succeeded_at).to be_present
      expect(sftp.failed?).to be(true)
      expect(sftp.last_error).to be_present

      expect(cbv_flow.transmitted_at).to be_present
      expect(cbv_flow.transmitted_at).to be_within(1.second).of(webhook.succeeded_at)
    end
  end

  context "when both methods fail" do
    let(:sftp_password) { "wrong-password-on-purpose" }
    let(:webhook_config) do
      { "webhook_url" => "http://localhost:9292/does-not-exist-404", "api_key" => "my-secure-guid" }
    end

    it "records both as failed and does not set cbv_flow.transmitted_at" do
      expect { CaseWorkerTransmitterJob.new.perform(cbv_flow.id) }.not_to raise_error

      cbv_flow.reload
      transmissions = cbv_flow.cbv_flow_transmissions

      expect(transmissions.pluck(:method_type)).to contain_exactly("webhook", "sftp")
      expect(transmissions.all?(&:failed?)).to be(true), "expected all failed; got: #{transmissions.map(&:status)}"
      expect(transmissions.all? { |t| t.last_error.present? }).to be(true)
      expect(cbv_flow.transmitted_at).to be_nil
    end
  end
end
