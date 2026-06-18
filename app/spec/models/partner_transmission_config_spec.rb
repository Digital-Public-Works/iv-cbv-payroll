require 'rails_helper'

RSpec.describe PartnerTransmissionConfig, type: :model do
  let(:cleartext) { "super-secret-123" }
  let(:partner_transmission_method) { create(:partner_transmission_method, partner_config: PartnerConfig.last) }

  describe "#value encryption logic" do
    context "when encrypted is true" do
      it "encrypts the data in the database" do
        ptc = PartnerTransmissionConfig.create!(key: "demo-config-item", is_encrypted: true, value: cleartext, partner_transmission_method: partner_transmission_method)

        expect(ptc.value).to eq(cleartext)

        raw_value = ptc.read_attribute(:value)
        expect(raw_value).not_to eq(cleartext)
        expect(raw_value).to include("==") # Encrypted strings usually have Base64 padding
      end
    end

    context "when encrypted is false" do
      it "stores the data as plain text" do
        ptc = PartnerTransmissionConfig.create!(key: "demo-config-item", is_encrypted: false, value: cleartext, partner_transmission_method: partner_transmission_method)

        raw_value = ptc.read_attribute(:value)
        expect(raw_value).to eq(cleartext)
      end
    end
  end
end
