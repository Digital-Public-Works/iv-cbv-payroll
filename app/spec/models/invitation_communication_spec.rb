require "rails_helper"

RSpec.describe InvitationCommunication, type: :model do
  it "is valid with a factory" do
    expect(build(:invitation_communication)).to be_valid
  end

  it "defaults to the created status" do
    expect(described_class.new.status).to eq("created")
  end

  it "rejects unknown channels and statuses" do
    expect { build(:invitation_communication, channel: "carrier_pigeon") }
      .to raise_error(ArgumentError, /'carrier_pigeon' is not a valid channel/)
    expect { build(:invitation_communication, status: "lost") }
      .to raise_error(ArgumentError, /'lost' is not a valid status/)
  end

  describe "#terminal?" do
    it "is terminal only when delivered or failed" do
      communication = build(:invitation_communication)

      aggregate_failures do
        %w[created sending sent].each do |status|
          communication.status = status
          expect(communication).not_to be_terminal
        end

        %w[delivered failed].each do |status|
          communication.status = status
          expect(communication).to be_terminal
        end
      end
    end
  end
end
