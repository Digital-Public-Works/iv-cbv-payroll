require 'rails_helper'
require 'csv'

RSpec.describe CsvToSftpReportDelivererJob, type: :job do
  let(:sftp_gateway) { instance_double(SftpGateway) }

  before do
    allow(SftpGateway).to receive(:new).and_return(sftp_gateway)
  end

  describe "#perform" do
    let(:authorized_timestamp) { Time.find_zone("UTC").local(2025, 1, 1, 10) }
    let(:transmitted_at) { Time.find_zone("UTC").local(2025, 5, 1, 1) }
    let(:expected_csv_headers) do
      %w[case_number confirmation_code cbv_link_created_timestamp cbv_link_clicked_timestamp
         report_created_timestamp consent_timestamp pdf_filename pdf_filetype language]
    end

    {
      "az_des" => { timezone: "America/Phoenix", expected_consent_timestamp: "01/01/2025 03:00:00" },
      "pa_dhs" => { timezone: "America/New_York", expected_consent_timestamp: "01/01/2025 05:00:00" }
    }.each do |partner_id, config|
      context "when partner is #{partner_id}" do
        it "generates csv when there are cases submitted during the time period" do
          cbv_flow = create(:cbv_flow, :completed, :invited, client_agency_id: partner_id,
                            consented_to_authorized_use_at: authorized_timestamp,
                            transmitted_at: transmitted_at)
          cbv_flow.cbv_applicant.update!(case_number: "12345")

          agency = ClientAgencyConfig.instance[partner_id]
          allow(agency).to receive(:transmission_configuration_for).with("sftp").and_return(
            { "sftp_directory" => "test" }.with_indifferent_access
          )

          expect(sftp_gateway).to receive(:upload_data) do |raw_csv, filename|
            expect(filename).to eq("test/20250401_summary.csv")
            csv = CSV.parse(raw_csv, headers: true)
            expect(csv.headers).to eq(expected_csv_headers)
            row = csv.first
            expect(row["case_number"]).to eq("12345")
            expect(row["consent_timestamp"]).to eq(config[:expected_consent_timestamp])
            expect(row["pdf_filename"]).to eq("CBVPilot_00012345_20250101_ConfSANDBOX0010002.pdf")
          end

          described_class.perform_now(partner_id, Date.new(2025, 4, 1), Date.new(2025, 5, 2))
        end

        it "does not upload when the agency has no sftp transmission method" do
          create(:cbv_flow, :completed, :invited, client_agency_id: partner_id,
                 consented_to_authorized_use_at: authorized_timestamp,
                 transmitted_at: transmitted_at)

          agency = ClientAgencyConfig.instance[partner_id]
          allow(agency).to receive(:transmission_configuration_for).with("sftp").and_return(
            {}.with_indifferent_access
          )

          expect(sftp_gateway).not_to receive(:upload_data)

          described_class.perform_now(partner_id, Date.new(2025, 4, 1), Date.new(2025, 5, 2))
        end

        it "does not generate csv when there are no cases submitted during the time period" do
          create(:cbv_flow, :completed, :invited, client_agency_id: partner_id, transmitted_at: 11.minutes.ago)
          create(:cbv_flow, :completed, :invited, client_agency_id: "sandbox", transmitted_at: 4.minutes.ago)

          expect(sftp_gateway).not_to receive(:upload_data)

          described_class.perform_now(partner_id, 10.minutes.ago, Time.current)
        end
      end
    end
  end
end
