require 'rails_helper'

RSpec.describe ClientAgency::ReportFields, type: :service do
  describe ".caseworker_specific_fields" do
    context "partner with show_on_caseworker_report attributes" do
      let(:cbv_flow) { create(:cbv_flow, client_agency_id: "az_des") }

      it "returns fields flagged for caseworker report" do
        fields = described_class.caseworker_specific_fields(cbv_flow)
        field_keys = fields.map(&:first)

        expect(field_keys).to include(".pdf.caseworker.case_number")
      end
    end

    context "partner with no show_on_caseworker_report attribute" do
      let(:cbv_flow) { create(:cbv_flow, client_agency_id: "sandbox") }

      it "returns empty array" do
        fields = described_class.caseworker_specific_fields(cbv_flow)

        expect(fields).to eq([])
      end
    end
  end

  describe ".applicant_specific_fields" do
    let(:cbv_flow) { create(:cbv_flow, client_agency_id: "sandbox") }

    it "returns the additional jobs field" do
      fields = described_class.applicant_specific_fields(cbv_flow)
      field_keys = fields.map(&:first)

      expect(field_keys).to include(a_string_matching(/additional_jobs_to_report/))
    end
  end
end
