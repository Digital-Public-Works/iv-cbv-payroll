require 'rails_helper'

RSpec.describe CbvApplicant, type: :model do
  describe "all valid types of agencies" do
    ClientAgencyConfig.instance.client_agency_ids.each do |client_agency_id|
      it "has a list of VALID_ATTRIBUTES for #{client_agency_id}" do
        expect(described_class.valid_attributes_for_agency(client_agency_id)).to be_present
      end
    end
  end

  # The seeded sandbox partner asks for first_name, middle_name, last_name,
  # date_of_birth and case_number on `applicant_input_page`; only middle_name is optional.
  describe "#missing_required_attributes_for" do
    let(:context) { PartnerAttributeUsage::APPLICANT_INPUT_PAGE }

    it "includes required attributes with no value" do
      applicant = build(:cbv_applicant, :sandbox, first_name: nil)

      expect(applicant.missing_required_attributes_for(context)).to include("first_name")
    end

    it "is empty when every required attribute has a value" do
      applicant = build(:cbv_applicant, :sandbox)

      expect(applicant.missing_required_attributes_for(context)).to be_empty
    end

    it "ignores an attribute the partner marks optional in that context" do
      applicant = build(:cbv_applicant, :sandbox, middle_name: nil)

      expect(applicant.missing_required_attributes_for(context)).to be_empty
    end
  end

  describe "#missing_attributes_for" do
    it "includes optional attributes that are still blank, so a page can ask for them" do
      applicant = build(:cbv_applicant, :sandbox, middle_name: nil)

      expect(applicant.missing_attributes_for(PartnerAttributeUsage::APPLICANT_INPUT_PAGE)).to eq([ "middle_name" ])
    end
  end

  describe "#validate_user_input" do
    let(:context) { PartnerAttributeUsage::APPLICANT_INPUT_PAGE }

    it "fails and adds an error for each required attribute with no value" do
      applicant = build(:cbv_applicant, :sandbox, date_of_birth: nil)

      expect(applicant.validate_user_input(context)).to be false
      expect(applicant.errors[:date_of_birth]).to include(
        I18n.t("cbv.applicant_informations.sandbox.fields.date_of_birth.blank")
      )
    end

    it "passes when every required attribute has a value" do
      applicant = build(:cbv_applicant, :sandbox, case_number: "123")

      expect(applicant.validate_user_input(context)).to be true
      expect(applicant.errors).to be_empty
    end

    context "when the attribute has a validation_regex" do
      before do
        allow_any_instance_of(ClientAgencyConfig::ClientAgency)
          .to receive(:validation_regex_for).and_return(nil)
        allow_any_instance_of(ClientAgencyConfig::ClientAgency)
          .to receive(:validation_regex_for).with("case_number").and_return('\A\d{8}\z')
      end

      it "rejects a submitted value that does not match" do
        applicant = build(:cbv_applicant, :sandbox, case_number: "nope")

        expect(applicant.validate_user_input(context, submitted_names: [ "case_number" ])).to be false
        expect(applicant.errors[:case_number]).to be_present
      end

      it "accepts a submitted value that matches" do
        applicant = build(:cbv_applicant, :sandbox, case_number: "12345678")

        expect(applicant.validate_user_input(context, submitted_names: [ "case_number" ])).to be true
      end

      it "leaves a value that was not submitted on this page alone" do
        applicant = build(:cbv_applicant, :sandbox, case_number: "nope")

        expect(applicant.validate_user_input(context, submitted_names: [])).to be true
      end

      it "does not reject a blank optional value" do
        applicant = build(:cbv_applicant, :sandbox, middle_name: nil)

        expect(applicant.validate_user_input(context, submitted_names: [ "middle_name" ])).to be true
      end
    end

    context "when an attribute is required_for_submit" do
      before do
        allow_any_instance_of(ClientAgencyConfig::ClientAgency)
          .to receive(:required_for_submit_attributes).and_return([ "middle_name" ])
      end

      it "blocks the applicant_input_page step while it is blank, even though it is optional there" do
        applicant = build(:cbv_applicant, :sandbox, middle_name: nil)

        expect(applicant.validate_user_input(PartnerAttributeUsage::APPLICANT_INPUT_PAGE)).to be false
        expect(applicant.errors[:middle_name]).to be_present
      end
    end
  end

  describe "#fields_to_collect_for" do
    it "asks only for what is still blank" do
      applicant = build(:cbv_applicant, :sandbox, first_name: nil, middle_name: nil)

      expect(applicant.fields_to_collect_for(PartnerAttributeUsage::APPLICANT_INPUT_PAGE))
        .to match_array(%w[first_name middle_name])
    end

    it "leaves a value that arrived on the invitation hidden" do
      applicant = build(:cbv_applicant, :sandbox)

      expect(applicant.fields_to_collect_for(PartnerAttributeUsage::APPLICANT_INPUT_PAGE))
        .not_to include("first_name")
    end

    it "keeps the partner's configured order" do
      applicant = build(:cbv_applicant, :sandbox, first_name: nil, last_name: nil)

      expect(applicant.fields_to_collect_for(PartnerAttributeUsage::APPLICANT_INPUT_PAGE))
        .to eq(%w[first_name last_name])
    end

    it "includes a blank required_for_submit attribute so it is always reachable" do
      allow_any_instance_of(ClientAgencyConfig::ClientAgency)
        .to receive(:required_for_submit_attributes).and_return([ "beacon_id" ])
      applicant = build(:cbv_applicant, :sandbox)

      expect(applicant.fields_to_collect_for(PartnerAttributeUsage::APPLICANT_INPUT_PAGE)).to include("beacon_id")
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
          case_number: "REDACTED" # partner_identifier is always redacted
        )
      end

      it "redacts specific fields when given" do
        applicant.redact!({ case_number: :string })

        expect(applicant.case_number).to eq("REDACTED")
      end
    end

    context "partner with date-redactable fields" do
      let(:applicant) { create(:cbv_applicant, :sandbox) }

      it "redacts date_of_birth" do
        applicant.redact!

        expect(applicant).to have_attributes(
          date_of_birth: Date.new(1990, 1, 1),
          case_number: "REDACTED" # partner_identifier is always redacted
        )
      end
    end

    context "partner with no applicant-level redactable fields (e.g. pa_dhs)" do
      let(:applicant) { create(:cbv_applicant, :pa_dhs) }

      it "marks the applicant redacted without raising" do
        expect { applicant.redact! }.not_to raise_error
        expect(applicant.reload.redacted_at).to be_within(1.second).of(Time.now)
      end

      it "always redacts the partner_identifier (case_number), even when not configured redactable" do
        expect(applicant.partner_identifier).to be_present
        applicant.redact!

        expect(applicant.reload.partner_identifier).to eq("REDACTED")
      end

      it "still redacts member_name in income_changes JSON" do
        applicant.redact!

        expect(applicant.income_changes).to be_present
        applicant.income_changes.each do |ic|
          expect(ic["member_name"]).to eq("REDACTED")
        end
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
      applicant = create(:cbv_applicant, :sandbox)

      expect(applicant.agency_expected_names).to eq([])
    end

    it "returns empty array when redacted" do
      applicant = create(:cbv_applicant, :az_des)
      applicant.redact!

      expect(applicant.agency_expected_names).to eq([])
    end
  end

  describe "#set_applicant_attributes" do
    let(:cbv_applicant) { build(:cbv_applicant, :sandbox) }

    it "sets the partner's applicant attributes" do
      cbv_applicant.set_applicant_attributes

      expect(cbv_applicant.applicant_attributes).to include(:first_name, :middle_name, :date_of_birth)
      expect(cbv_applicant.applicant_attributes).to all(be_a(Symbol))
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
        applicant = described_class.new(valid_attributes)
        expect(applicant).to be_valid
        expect(applicant.snap_application_date).to eq(Date.current)
      end

      it "requires a snap_application_date in the caseworker workflow" do
        applicant = described_class.new(valid_attributes)
        applicant.snap_application_date = nil
        expect(applicant).not_to be_valid
      end

      it "allows snap_application_date in the future for sandbox agency" do
        applicant = described_class.new(valid_attributes)
        applicant.snap_application_date = Date.tomorrow
        expect(applicant).to be_valid
      end

      it "parses snap_application_date strings correctly" do
        applicant = described_class.new(valid_attributes)
        applicant.snap_application_date = "08/15/2023"
        expect(applicant).to be_valid
        expect(applicant.snap_application_date).to eq(Date.new(2023, 8, 15))
      end

      it "adds an error when snap_application_date is not a valid date in a caseworker workflow" do
        applicant = described_class.new(valid_attributes)
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
              "case_number" => { "required" => false },
              "first_name" => { "required" => true },
              "middle_name" => { "required" => false },
              "last_name" => { "required" => false },
              "date_of_birth" => { "required" => true, "type" => "date" }
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
