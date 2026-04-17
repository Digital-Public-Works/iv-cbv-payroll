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
      "password" => "testpass",
      "url" => "localhost",
      "port" => "2222",
      "sftp_directory" => "upload"
    }
  end

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

  before do
    allow(Aggregators::AggregatorReports::ArgyleReport).to receive(:new).and_return(argyle_report)

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

  it "fans out to both webhook and SFTP in a single job run" do
    expect { CaseWorkerTransmitterJob.new.perform(cbv_flow.id) }.not_to raise_error

    transmission = CbvFlowTransmission.find_by!(cbv_flow: cbv_flow)
    attempts = transmission.cbv_flow_transmission_attempts

    expect(attempts.pluck(:method_type)).to contain_exactly("webhook", "sftp")
    expect(attempts.all? { |a| a.succeeded? }).to be(true), "all attempts should succeed; got: #{attempts.map(&:status)}"
    expect(transmission.reload.succeeded?).to be(true)
    expect(cbv_flow.reload.transmitted_at).to be_present
  end
end
