require "rails_helper"

RSpec.describe Aggregators::Sdk::MockArgyleService do
  # These exercise the demo fixtures that back the pay stub images feature
  # (paystubs_all_images / paystubs_some_images / paystubs_no_images), all
  # derived from busy_joe's three employers.
  ARAMARK = "01959b15-8b7f-5487-212d-2c0f50e3ec96".freeze
  TARGET  = "01958c05-982e-0ff3-47d8-9d469d6d7957".freeze
  WALMART = "01959b16-5b52-2e43-ffcc-06bc8717eb8b".freeze

  def service(fixture_user)
    described_class.new(:mock, fixture_user: fixture_user)
  end

  describe "fixture user selection" do
    it "defaults to bob" do
      expect(described_class.new(:mock).instance_variable_get(:@fixture_user)).to eq("bob")
    end

    it "honors an explicit fixture_user argument" do
      expect(service("paystubs_some_images").instance_variable_get(:@fixture_user)).to eq("paystubs_some_images")
    end

    it "falls back to the MOCK_ARGYLE_FIXTURE_USER env var" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("MOCK_ARGYLE_FIXTURE_USER").and_return("paystubs_no_images")
      expect(described_class.new(:mock).instance_variable_get(:@fixture_user)).to eq("paystubs_no_images")
    end
  end

  describe "#fetch_paystubs_api" do
    it "returns only the requested account's paystubs for a multi-employer fixture" do
      results = service("paystubs_some_images").fetch_paystubs_api(account: ARAMARK)["results"]
      expect(results).to be_present
      expect(results.map { |p| p["account"] }.uniq).to eq([ ARAMARK ])
    end

    it "returns the whole payload when the account is unknown (legacy fallback)" do
      all = service("paystubs_some_images").fetch_paystubs_api(account: nil)["results"]
      expect(all.map { |p| p["account"] }.uniq).to contain_exactly(ARAMARK, TARGET, WALMART)
    end
  end

  describe "#fetch_payroll_documents_api" do
    context "paystubs_some_images (plural fixture, per-account)" do
      it "returns a document for an account that has images" do
        docs = service("paystubs_some_images").fetch_payroll_documents_api(account: ARAMARK)["results"]
        expect(docs.size).to eq(1)
        expect(docs.first).to include("document_type" => "payout-statement")
        expect(docs.first["file_url"]).to be_present
      end

      it "returns no documents for an account without images" do
        docs = service("paystubs_some_images").fetch_payroll_documents_api(account: WALMART)["results"]
        expect(docs).to be_empty
      end
    end

    context "paystubs_no_images (no documents fixture)" do
      it "returns no documents for any account" do
        docs = service("paystubs_no_images").fetch_payroll_documents_api(account: ARAMARK)["results"]
        expect(docs).to be_empty
      end
    end

    context "bob (legacy singular fixture)" do
      it "still returns the single document unchanged" do
        docs = service("bob").fetch_payroll_documents_api(account: "any")["results"]
        expect(docs.size).to eq(1)
      end
    end
  end
end
