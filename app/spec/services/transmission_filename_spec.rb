require "rails_helper"

RSpec.describe TransmissionFilename do
  let(:consented_at) { Time.find_zone("UTC").local(2026, 5, 13, 14, 30) }
  let(:partner_identifier) { "12345" }
  let(:confirmation_code) { "ABC123" }
  let(:agency_id) { "new-partner" }  # non-legacy → VMI prefix
  let(:cbv_applicant) { create(:cbv_applicant, partner_identifier: partner_identifier) }
  let(:cbv_flow) do
    create(:cbv_flow,
      cbv_applicant: cbv_applicant,
      consented_to_authorized_use_at: consented_at,
      confirmation_code: confirmation_code
    )
  end
  let(:agency) { instance_double(ClientAgencyConfig::ClientAgency, id: agency_id, timezone: "America/New_York") }

  describe ".for" do
    it "produces the VMI stem with the sftp extension for non-legacy agencies" do
      expect(described_class.for(cbv_flow, agency, :sftp))
        .to eq("VMI_00012345_20260513_ConfABC123.pdf")
    end

    it "uses the same stem for unencrypted_s3 with .tar.gz" do
      expect(described_class.for(cbv_flow, agency, :unencrypted_s3))
        .to eq("VMI_00012345_20260513_ConfABC123.tar.gz")
    end

    it "uses the same stem for encrypted_s3 with .tar.gz.gpg" do
      expect(described_class.for(cbv_flow, agency, :encrypted_s3))
        .to eq("VMI_00012345_20260513_ConfABC123.tar.gz.gpg")
    end

    it "raises for non-file methods (webhook, shared_email, json have no filename)" do
      expect { described_class.for(cbv_flow, agency, :webhook) }.to raise_error(KeyError, /not a file-producing method/)
      expect { described_class.for(cbv_flow, agency, :shared_email) }.to raise_error(KeyError, /not a file-producing method/)
      expect { described_class.for(cbv_flow, agency, :json) }.to raise_error(KeyError, /not a file-producing method/)
    end

    it "accepts string method types" do
      expect(described_class.for(cbv_flow, agency, "sftp"))
        .to eq("VMI_00012345_20260513_ConfABC123.pdf")
    end

    context "for the legacy PA agency" do
      let(:agency_id) { "pa_dhs" }

      it "uses the CBVPilot legacy prefix" do
        expect(described_class.for(cbv_flow, agency, :sftp))
          .to eq("CBVPilot_00012345_20260513_ConfABC123.pdf")
      end
    end

    context "for the legacy AZ agency" do
      let(:agency_id) { "az_des" }

      it "uses the CBVPilot legacy prefix" do
        expect(described_class.for(cbv_flow, agency, :sftp))
          .to eq("CBVPilot_00012345_20260513_ConfABC123.pdf")
      end
    end

    context "with a short partner_identifier" do
      let(:partner_identifier) { "7" }

      it "pads to 8 digits" do
        expect(described_class.for(cbv_flow, agency, :sftp))
          .to eq("VMI_00000007_20260513_ConfABC123.pdf")
      end
    end

    context "with a UUID partner_identifier" do
      let(:partner_identifier) { "550e8400-e29b-41d4-a716-446655440000" }

      it "leaves it unchanged (already longer than 8 chars)" do
        expect(described_class.for(cbv_flow, agency, :sftp))
          .to eq("VMI_#{partner_identifier}_20260513_ConfABC123.pdf")
      end
    end

    context "when consent crosses a UTC/agency-tz day boundary" do
      let(:consented_at) { Time.find_zone("UTC").local(2026, 5, 13, 3) }

      it "renders the date in the agency timezone" do
        # 03:00 UTC on the 13th is still the 12th in America/New_York.
        expect(described_class.for(cbv_flow, agency, :sftp))
          .to eq("VMI_00012345_20260512_ConfABC123.pdf")
      end
    end

    context "when consent timestamp is missing" do
      let(:consented_at) { nil }

      it "raises an error naming consent timestamp as the missing input" do
        expect { described_class.for(cbv_flow, agency, :sftp) }
          .to raise_error(/consent timestamp/i)
      end
    end

    context "when the resulting filename would exceed 100 characters" do
      # Fixed template = "VMI_" + 8 + "_" + 8 + "_Conf" + extension
      # = 4 + 8 + 1 + 8 + 5 + 11 = 37 chars; leaves 63 for confirmation_code
      # to blow .tar.gz.gpg's budget. We use a synthetic 64-char code.
      let(:confirmation_code) { "X" * 64 }

      it "raises an error referencing the 100-char ceiling" do
        expect { described_class.for(cbv_flow, agency, :encrypted_s3) }
          .to raise_error(/100/)
      end
    end

    it "raises on an unknown method_type" do
      expect { described_class.for(cbv_flow, agency, :smoke_signal) }
        .to raise_error(KeyError, /not a file-producing method/)
    end
  end
end
