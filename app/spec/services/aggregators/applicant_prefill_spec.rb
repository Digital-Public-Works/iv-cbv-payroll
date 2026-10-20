require "rails_helper"

RSpec.describe Aggregators::ApplicantPrefill do
  let(:partner) { PartnerConfig.find_by(partner_id: "sandbox") }
  let(:cbv_flow) { create(:cbv_flow, cbv_applicant: create(:cbv_applicant, :blank)) }
  let(:applicant) { cbv_flow.cbv_applicant }

  def map(name, source_field)
    partner.partner_application_attributes.where(name: name.to_s).update_all(source_field: source_field)
    ClientAgencyConfig.reset!
  end

  def identity(**attrs)
    Aggregators::ResponseObjects::Identity.new(**attrs)
  end

  def prefill(*identities)
    described_class.new(cbv_flow.reload, identities).call
  end

  describe "mapping to normalized fields" do
    before { map(:first_name, "identity.first_name") }

    it "fills a blank attribute from the payroll response" do
      prefill(identity(first_name: "Daphne"))

      expect(applicant.reload.first_name).to eq("Daphne")
    end

    it "records the provider as the source, not the applicant" do
      prefill(identity(first_name: "Daphne"))

      expect(applicant.reload).not_to be_applicant_provided(:first_name)
      expect(applicant.provenance_for(:first_name)["source"]).to eq("payroll_provider")
    end

    it "leaves attributes the partner has not mapped alone" do
      prefill(identity(first_name: "Daphne", last_name: "Gold"))

      expect(applicant.reload.last_name).to be_nil
    end

    it "works the same whichever aggregator produced the identity" do
      argyle = Aggregators::ResponseObjects::Identity.from_argyle("first_name" => "Daphne")
      expect { described_class.new(cbv_flow, [ argyle ]).call }
        .to change { applicant.reload.first_name }.to("Daphne")
    end
  end

  describe "an absent value is still nil" do
    before { map(:first_name, "identity.first_name") }

    it "leaves the attribute blank when the provider has no value" do
      prefill(identity(first_name: nil))

      expect(applicant.reload.first_name).to be_nil
      expect(applicant.provenance_for(:first_name)).to be_nil
    end

    it "leaves it blank when the provider sends an empty string" do
      prefill(identity(first_name: "  "))

      expect(applicant.reload.first_name).to be_nil
    end

    it "so the applicant is still asked for it" do
      prefill(identity(first_name: nil))

      expect(applicant.reload.fields_to_collect_for(PartnerAttributeUsage::APPLICANT_INPUT_PAGE))
        .to include("first_name")
    end
  end

  describe "never overwriting what a person supplied" do
    before { map(:first_name, "identity.first_name") }

    it "leaves a value that came in on the invitation" do
      applicant.update!(first_name: "FromCaseworker")

      prefill(identity(first_name: "Daphne"))

      expect(applicant.reload.first_name).to eq("FromCaseworker")
    end

    it "leaves a value the applicant typed" do
      applicant.first_name = "Typed"
      applicant.record_attribute_provenance([ :first_name ])
      applicant.save!

      prefill(identity(first_name: "Daphne"))

      expect(applicant.reload.first_name).to eq("Typed")
      expect(applicant.reload).to be_applicant_provided(:first_name)
    end

    it "revises a value it supplied itself" do
      prefill(identity(first_name: "Daphne"))

      prefill(identity(first_name: "Daph"))

      expect(applicant.reload.first_name).to eq("Daph")
    end
  end

  describe "when synced accounts disagree" do
    before { map(:first_name, "identity.first_name") }

    it "fills when every account that has an opinion agrees" do
      prefill(identity(first_name: "Daphne"), identity(first_name: "Daphne"))

      expect(applicant.reload.first_name).to eq("Daphne")
    end

    it "ignores accounts with nothing to say" do
      prefill(identity(first_name: "Daphne"), identity(first_name: nil))

      expect(applicant.reload.first_name).to eq("Daphne")
    end

    it "leaves it blank when they contradict each other" do
      prefill(identity(first_name: "Daphne"), identity(first_name: "Bob"))

      expect(applicant.reload.first_name).to be_nil
    end

    it "withdraws a value it supplied once a later account contradicts it" do
      prefill(identity(first_name: "Daphne"))
      expect(applicant.reload.first_name).to eq("Daphne")

      prefill(identity(first_name: "Daphne"), identity(first_name: "Bob"))

      expect(applicant.reload.first_name).to be_nil
      expect(applicant.provenance_for(:first_name)).to be_nil
    end
  end

  describe "values that do not fit the partner's configuration" do
    it "coerces an ISO date from the provider into the date column" do
      map(:date_of_birth, "identity.date_of_birth")

      prefill(identity(date_of_birth: "1998-06-15"))

      expect(applicant.reload.date_of_birth).to eq(Date.new(1998, 6, 15))
    end

    it "treats a value failing the partner's validation_regex as no value" do
      map(:case_number, "identity.first_name")
      partner.partner_application_attributes.where(name: "case_number")
             .update_all(validation_regex: '\A\d{6}\z')
      ClientAgencyConfig.reset!

      prefill(identity(first_name: "Daphne"))

      expect(applicant.reload.case_number).to be_nil
    end

    it "accepts one that satisfies the regex" do
      map(:case_number, "identity.first_name")
      partner.partner_application_attributes.where(name: "case_number")
             .update_all(validation_regex: '\A\d{6}\z')
      ClientAgencyConfig.reset!

      prefill(identity(first_name: "123456"))

      expect(applicant.reload.case_number).to eq("123456")
    end

    it "takes the first usable entry from a list-valued field" do
      map(:first_name, "identity.emails")

      prefill(identity(emails: [ nil, "a@example.com", "b@example.com" ]))

      expect(applicant.reload.first_name).to eq("a@example.com")
    end
  end

  it "does nothing when the partner maps no attributes" do
    expect { prefill(identity(first_name: "Daphne")) }
      .not_to change { applicant.reload.attribute_provenance }
  end
end
