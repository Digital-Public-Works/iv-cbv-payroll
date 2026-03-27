require 'rails_helper'

RSpec.describe CbvApplicant, type: :model do
  describe "all valid types of agencies" do
    ClientAgencyConfig.instance.client_agency_ids.each do |client_agency_id|
      it "has a list of VALID_ATTRIBUTES for #{client_agency_id}" do
        expect(CbvApplicant.valid_attributes_for_agency(client_agency_id)).to be_present
      end
    end
  end

  describe "#has_applicant_attribute_missing?" do
    before do
      allow_any_instance_of(ClientAgencyConfig::ClientAgency).to receive(:applicant_attributes).and_return(
        { first_name: "required" }
      )
    end

    let(:cbv_applicant) { create(:cbv_applicant, first_name: nil) }
    it "returns true if a field missing" do
      cbv_applicant.set_applicant_attributes
      expect(cbv_applicant.required_applicant_attributes).to be_present
      expect(cbv_applicant.has_applicant_attribute_missing?).to eq(true)
    end

    it "returns false if a field not missing" do
      cbv_applicant.set_applicant_attributes
      cbv_applicant.first_name = "Dean Venture"
      expect(cbv_applicant.has_applicant_attribute_missing?).to eq(false)
    end
  end

  describe "#validate_required_applicant_attributes" do
    let(:date_of_birth) { build(:cbv_applicant).date_of_birth }

    it "returns an array of symbols containing the missing field keys" do
      cbv_applicant_without_case_number = build(:cbv_applicant, :sandbox, middle_name: nil)
      cbv_applicant_without_case_number.set_applicant_attributes
      expect(cbv_applicant_without_case_number.required_applicant_attributes).to be_present
      expect(cbv_applicant_without_case_number.case_number).to be_nil
      expect(cbv_applicant_without_case_number.validate_required_applicant_attributes).to eq([ :case_number ])
    end

    it "is adds errors to the model instance when required field is missing" do
      cbv_applicant_without_dob = build(:cbv_applicant, :sandbox, date_of_birth: nil)
      cbv_applicant_without_dob.set_applicant_attributes
      cbv_applicant_without_dob.validate_required_applicant_attributes
      expect(cbv_applicant_without_dob.errors[:date_of_birth]).to include(I18n.t("cbv.applicant_informations.sandbox.fields.date_of_birth.blank"))
    end

    it "it returns an empty array when validation constraints are met" do
      valid_cbv_applicant = build(:cbv_applicant, :sandbox, date_of_birth: date_of_birth, case_number: '123')
      valid_cbv_applicant.set_applicant_attributes
      valid_cbv_applicant.validate_required_applicant_attributes
      expect(valid_cbv_applicant.errors).to be_empty
    end

    context "partner where case_number is required (az_des)" do
      let(:applicant) { build(:cbv_applicant, :az_des, case_number: nil) }

      it "reports case_number as missing" do
        applicant.set_applicant_attributes
        missing = applicant.validate_required_applicant_attributes

        expect(missing).to include(:case_number)
        expect(applicant.errors[:case_number]).to include(
          I18n.t("cbv.applicant_informations.az_des.fields.case_number.blank")
        )
      end
    end

    context "partner where case_number is optional (la_ldh)" do
      let(:applicant) { build(:cbv_applicant, :la_ldh, case_number: nil) }

      it "does not report case_number as missing" do
        applicant.set_applicant_attributes
        missing = applicant.validate_required_applicant_attributes

        expect(missing).not_to include(:case_number)
        expect(applicant).to be_valid
      end
    end
  end

  describe "#redact!" do
    context "partner with string-redactable fields" do
      let(:applicant) { create(:cbv_applicant, :az_des) }

      it "redacts all sensitive PII fields" do
        applicant.redact!

        expect(applicant).to have_attributes(
          first_name: "REDACTED",
          middle_name: "REDACTED",
          last_name: "REDACTED",
          case_number: /[0-9]+/
        )
      end

      it "redacts specific fields when given" do
        applicant.redact!({ case_number: :string })

        expect(applicant.case_number).to eq("REDACTED")
      end
    end

    context "partner with date-redactable fields" do
      let(:applicant) { create(:cbv_applicant, :la_ldh) }

      it "redacts date_of_birth" do
        applicant.redact!

        expect(applicant).to have_attributes(
          date_of_birth: Date.new(1990, 1, 1),
          case_number: /[0-9]+/
        )
      end
    end

    context "income_changes redaction" do
      let(:applicant) { create(:cbv_applicant, :az_des) }

      it "redacts member_name in income_changes JSON" do
        applicant.redact!

        expect(applicant.income_changes).to be_present
        applicant.income_changes.each do |ic|
          expect(ic["member_name"]).to eq("REDACTED")
          expect(ic["employer_name"]).not_to eq("REDACTED")
        end
      end

      it "handles non-array income_changes" do
        applicant.income_changes = "this is not an array"
        applicant.redact!

        expect(applicant.income_changes).to eq("this is not an array")
      end

      it "handles nil/missing member_name" do
        applicant.income_changes = [
          { "member_name" => nil, "employer_name" => "Test Company" },
          { "employer_name" => "Missing Company" }
        ]

        applicant.redact!

        expect(applicant.income_changes).to eq([
          { "member_name" => "REDACTED", "employer_name" => "Test Company" },
          { "employer_name" => "Missing Company" }
        ])
      end
    end
  end

  describe "#agency_expected_names" do
    it "returns unique member names from income_changes" do
      applicant = create(:cbv_applicant, :az_des)

      expect(applicant.agency_expected_names).to eq([ "Mark Scout" ])
    end

    it "returns empty array when income_changes is blank" do
      applicant = create(:cbv_applicant, :la_ldh)

      expect(applicant.agency_expected_names).to eq([])
    end

    it "returns empty array when redacted" do
      applicant = create(:cbv_applicant, :az_des)
      applicant.redact!

      expect(applicant.agency_expected_names).to eq([])
    end
  end

  describe "#validate_base_and_applicant_attributes?" do
    let(:valid_applicant) { build(:cbv_applicant, :sandbox, case_number: '123') }
    let(:invalid_applicant) { build(:cbv_applicant, :sandbox, date_of_birth: nil, case_number: nil) }

    it "returns true when all validation methods pass" do
      valid_applicant.set_applicant_attributes
      expect(valid_applicant.validate_base_and_applicant_attributes?).to be true
    end

    it "returns false when validate_required_applicant_attributes contains entries" do
      invalid_applicant.set_applicant_attributes
      expect(invalid_applicant.validate_base_and_applicant_attributes?).to be false
    end
  end

  describe "#set_applicant_attributes" do
    let(:cbv_applicant) { build(:cbv_applicant, :sandbox) }

    it "sets applicant and required attributes based on agency config" do
      cbv_applicant.set_applicant_attributes

      expect(cbv_applicant.applicant_attributes).to include(:first_name, :middle_name, :date_of_birth)
      expect(cbv_applicant.applicant_attributes).to all(be_a(Symbol))

      expect(cbv_applicant.required_applicant_attributes).to include(:first_name, :date_of_birth)
      expect(cbv_applicant.required_applicant_attributes).not_to include(:middle_name)
    end
  end

  describe "ActiveRecord::Base validations" do
    let(:valid_attributes) { attributes_for(:cbv_applicant, :sandbox) }

    describe "middle_name" do
      it "allows middle_name to be optional" do
        applicant = create(:cbv_applicant, middle_name: nil)
        expect(applicant).to be_valid
      end
    end

    describe "snap_application_date" do
      it "does not require snap_application_date in the generic link workflow, sets default" do
        applicant = CbvApplicant.new(valid_attributes)
        expect(applicant).to be_valid
        expect(applicant.snap_application_date).to eq(Date.current)
      end

      it "requires a snap_application_date in the caseworker workflow" do
        applicant = CbvApplicant.new(valid_attributes)
        applicant.snap_application_date = nil
        expect(applicant).not_to be_valid
      end

      it "allows snap_application_date in the future for sandbox agency" do
        applicant = CbvApplicant.new(valid_attributes)
        applicant.snap_application_date = Date.tomorrow
        expect(applicant).to be_valid
      end

      it "parses snap_application_date strings correctly" do
        applicant = CbvApplicant.new(valid_attributes)
        applicant.snap_application_date = "08/15/2023"
        expect(applicant).to be_valid
        expect(applicant.snap_application_date).to eq(Date.new(2023, 8, 15))
      end

      it "adds an error when snap_application_date is not a valid date in a caseworker workflow" do
        applicant = CbvApplicant.new(valid_attributes)
        applicant.snap_application_date = "invalid"
        expect(applicant).not_to be_valid
        expect(applicant.errors[:snap_application_date]).to include(
          I18n.t('activerecord.errors.models.cbv_applicant.attributes.snap_application_date.invalid_date')
        )
      end
    end

    describe "date_of_birth" do
      let(:date_of_birth) { Date.new(1980, 1, 1) }

      context "agency with date_of_birth required" do
        before do
          allow_any_instance_of(ClientAgencyConfig::ClientAgency).to receive(:applicant_attributes).and_return(
            {
              first_name: { "required" => true },
              date_of_birth: { "required" => true, "type" => "date" }
            }
          )
        end

        it "adds an error when date_of_birth is in the future" do
          applicant = build(:cbv_applicant, :sandbox, date_of_birth: Date.tomorrow)
          applicant.valid?
          expect(applicant.errors[:date_of_birth]).to include(
            I18n.t('activerecord.errors.models.cbv_applicant/sandbox.attributes.date_of_birth.future_date')
          )
        end

        it "adds an error when date_of_birth is more than 110 years in the past" do
          applicant = build(:cbv_applicant, :sandbox, date_of_birth: 111.years.ago.to_date)
          applicant.valid?
          expect(applicant.errors[:date_of_birth]).to include(
            I18n.t('activerecord.errors.models.cbv_applicant/sandbox.attributes.date_of_birth.invalid_date')
          )
        end
      end
    end
  end
end
