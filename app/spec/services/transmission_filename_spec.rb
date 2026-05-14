require "rails_helper"

RSpec.describe TransmissionFilename do
  let(:consented_at) { Time.find_zone("UTC").local(2026, 5, 13, 14, 30) }
  let(:cbv_applicant) { create(:cbv_applicant, partner_identifier: "12345") }
  let(:cbv_flow) do
    create(:cbv_flow,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: consented_at,
      confirmation_code: "ABC123"
    )
  end
  let(:agency) { instance_double(ClientAgencyConfig::ClientAgency, timezone: "America/New_York") }

  describe ".for" do
    it "produces the unified CBVPilot stem with the sftp extension" do
      expect(described_class.for(cbv_flow, agency, :sftp))
        .to eq("CBVPilot_00012345_20260513_ConfABC123.pdf")
    end

    it "uses the same stem for unencrypted_s3 with .tar.gz" do
      expect(described_class.for(cbv_flow, agency, :unencrypted_s3))
        .to eq("CBVPilot_00012345_20260513_ConfABC123.tar.gz")
    end

    it "uses the same stem for encrypted_s3 with .tar.gz.gpg" do
      expect(described_class.for(cbv_flow, agency, :encrypted_s3))
        .to eq("CBVPilot_00012345_20260513_ConfABC123.tar.gz.gpg")
    end

    it "returns the bare stem for webhook (no extension)" do
      expect(described_class.for(cbv_flow, agency, :webhook))
        .to eq("CBVPilot_00012345_20260513_ConfABC123")
    end

    it "accepts string method types" do
      expect(described_class.for(cbv_flow, agency, "sftp"))
        .to eq("CBVPilot_00012345_20260513_ConfABC123.pdf")
    end

    it "pads partner_identifier to 8 digits" do
      cbv_applicant.update!(partner_identifier: "7")
      expect(described_class.for(cbv_flow, agency, :sftp))
        .to eq("CBVPilot_00000007_20260513_ConfABC123.pdf")
    end

    it "renders the date in the agency timezone" do
      # Consent at 2026-05-13 03:00 UTC is still 2026-05-12 in America/New_York
      cbv_flow.update!(consented_to_authorized_use_at: Time.find_zone("UTC").local(2026, 5, 13, 3))
      expect(described_class.for(cbv_flow, agency, :sftp))
        .to eq("CBVPilot_00012345_20260512_ConfABC123.pdf")
    end

    it "raises when consented_to_authorized_use_at is nil" do
      cbv_flow.update!(consented_to_authorized_use_at: nil)
      expect { described_class.for(cbv_flow, agency, :sftp) }
        .to raise_error(/consent timestamp/i)
    end

    it "raises when the total length would exceed 100 characters" do
      # The encrypted_s3 extension (.tar.gz.gpg = 11) leaves 89 chars for the stem.
      # Fixed stem template = CBVPilot_<8>_<8>_Conf = 31 chars, leaving 58 for confirmation_code.
      cbv_flow.update!(confirmation_code: "X" * 59)
      expect { described_class.for(cbv_flow, agency, :encrypted_s3) }
        .to raise_error(/100/)
    end

    it "raises on an unknown method_type" do
      expect { described_class.for(cbv_flow, agency, :smoke_signal) }
        .to raise_error(KeyError)
    end
  end
end
