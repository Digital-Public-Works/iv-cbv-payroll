require "rails_helper"

RSpec.describe Transmitters::SftpTransmitter, integration: true do
  # Fixed consent timestamp keeps the basename deterministic across runs.
  let(:consented_at) { Time.zone.local(2026, 5, 27, 12, 0, 0) }
  let(:cbv_applicant) { create(:cbv_applicant, case_number: "ABC1234") }
  let(:cbv_flow) do
    create(:cbv_flow,
      :invited,
      :with_argyle_account,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: consented_at,
      confirmation_code: "SFTP001",
      client_agency_id: "pa_dhs"
    )
  end

  let(:mock_client_agency) { instance_double(ClientAgencyConfig::ClientAgency) }
  let(:argyle_report) { build(:argyle_report, :with_argyle_account) }
  let(:aggregator_report) do
    Aggregators::AggregatorReports::CompositeReport.new(
      [ argyle_report ],
      days_to_fetch_for_w2: 90,
      days_to_fetch_for_gig: 90
    )
  end

  let(:transmission_method_configuration) do
    {
      "user" => "testuser",
      "password" => "testpass",
      "url" => "localhost",
      "port" => "2222",
      "path_prefix" => "upload"
    }
  end

  before do
    allow(mock_client_agency).to receive(:id).and_return("pa_dhs")
    allow(mock_client_agency).to receive(:logo_path).and_return("pa_compass_logo.svg")
    allow(mock_client_agency).to receive(:report_customization_show_earnings_list).and_return(true)
    allow(mock_client_agency).to receive(:timezone).and_return("America/New_York")

    stub_pdf_generation(label: "SftpTransmitter integration test")

    # Use password-only auth to avoid scanning local ~/.ssh keys (which may
    # include ed25519 keys that require an optional gem not in the bundle).
    allow(Net::SSH).to receive(:start).and_wrap_original do |original, host, user, **opts|
      original.call(host, user, **opts.merge(
        verify_host_key: :never,
        keys: [],
        auth_methods: %w[password]
      ))
    end
  end

  subject { described_class.new(cbv_flow, mock_client_agency, aggregator_report, transmission_method_configuration) }

  # The atmoz/sftp container mounts the host's sftp_mount_root to the container's home dir
  let(:sftp_mount_root) { Rails.root.join("tmp/integration_transmissions/sftp") }
  let(:expected_basename) { "CBVPilot_0ABC1234_20260527_ConfSFTP001.pdf" }

  describe "#deliver" do
    before do
      # Clear any PDFs left by prior runs so file-existence checks are unambiguous.
      Dir.glob(sftp_mount_root.join("**/*.pdf")).each { |f| FileUtils.rm_f(f) }
    end

    it "uploads the PDF under the configured path_prefix" do
      expect { subject.deliver }.not_to raise_error

      landed = sftp_mount_root.join(expected_basename)
      expect(landed).to exist,
        "expected PDF at #{landed}, saw: #{Dir.children(sftp_mount_root).inspect}"
    end

    context "when path_prefix is a nested directory" do
      let(:transmission_method_configuration) do
        {
          "user" => "testuser",
          "password" => "testpass",
          "url" => "localhost",
          "port" => "2222",
          "path_prefix" => "upload/inbox/prod"
        }
      end

      it "uploads the PDF under the nested prefix" do
        # Create the nested dir via SFTP so it's owned by the container's testuser
        ssh = Net::SSH.start("localhost", "testuser",
          password: "testpass", port: 2222,
          keys: [], auth_methods: %w[password], non_interactive: true)
        begin
          sftp = Net::SFTP::Session.new(ssh).connect!
          %w[upload/inbox upload/inbox/prod].each do |dir|
            begin
              sftp.mkdir!(dir)
            rescue Net::SFTP::StatusException
              # already exists from a prior run — fine
            end
          end
        ensure
          ssh.close
        end

        expect { subject.deliver }.not_to raise_error

        landed = sftp_mount_root.join("inbox/prod", expected_basename)
        expect(landed).to exist,
          "expected PDF at #{landed}, saw: #{Dir.children(sftp_mount_root.join('inbox/prod')).inspect}"
      end
    end
  end

  describe "with bad credentials" do
    it "fails the transmission and records the error" do
      bad_config = transmission_method_configuration.merge("password" => "wrong-password")
      transmission = create(:cbv_flow_transmission,
        cbv_flow: cbv_flow,
        method_type: :sftp,
        status: :pending,
        configuration: bad_config
      )

      allow_any_instance_of(CbvFlowTransmissionJob).to receive(:set_aggregator_report).and_return(aggregator_report)
      allow_any_instance_of(CbvFlowTransmissionJob).to receive(:event_logger)
        .and_return(instance_double(GenericEventTracker, track: nil))

      expect {
        CbvFlowTransmissionJob.new.perform(transmission.id)
      }.to raise_error(Net::SSH::AuthenticationFailed)

      transmission.reload
      expect(transmission).to be_failed
      expect(transmission.last_error).to be_present
      expect(transmission.succeeded_at).to be_nil
      expect(cbv_flow.reload.transmitted_at).to be_nil
    end
  end
end
