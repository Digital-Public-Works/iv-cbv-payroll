require "rails_helper"

RSpec.describe Aggregators::ResponseObjects::PaymentAccount, type: :model do
  describe ".from_argyle" do
    it "builds an ACH account from an ach_deposit_account destination" do
      account = described_class.from_argyle(
        "ach_deposit_account" => { "account_number" => "xxxxxx1111" }
      )

      expect(account.account_type).to eq("ach_deposit_account")
      expect(account.category).to eq("ach")
      expect(account.last_four).to eq("1111")
      expect(account).to be_ach
      expect(account).not_to be_card
    end

    it "builds a card account from a card destination" do
      account = described_class.from_argyle(
        "card" => { "name" => "Payout Card", "number" => "xxxxxx9122" }
      )

      expect(account.account_type).to eq("card")
      expect(account.category).to eq("card")
      expect(account.last_four).to eq("9122")
      expect(account).to be_card
      expect(account).not_to be_ach
    end

    it "returns nil for a destination with neither an account nor a card" do
      expect(described_class.from_argyle("ach_deposit_account" => nil, "card" => nil)).to be_nil
    end

    it "returns nil when the account number has no digits" do
      expect(
        described_class.from_argyle("ach_deposit_account" => { "account_number" => "xxxxxx" })
      ).to be_nil
    end

    it "returns nil for a blank destination" do
      expect(described_class.from_argyle(nil)).to be_nil
    end
  end

  describe "#to_output" do
    it "serializes to a translated type and last_four" do
      account = described_class.new(account_type: "card", last_four: "9122")

      expect(account.to_output).to eq(type: "card", last_four: "9122")
    end
  end
end
