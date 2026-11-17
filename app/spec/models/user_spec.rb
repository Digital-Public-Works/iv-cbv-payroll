require 'rails_helper'

RSpec.describe User, type: :model do
  it "finds a user by access token" do
    user = create(:user, :with_access_token, is_service_account: true)
    token = user.api_access_tokens.first.access_token
    found_user = described_class.find_by_access_token(token)
    expect(found_user.id).to eq(user.id)
  end

  it "rejects an access token if it's marked as deleted" do
    user = create(:user, :with_access_token, is_service_account: true)
    token = user.api_access_tokens.first.access_token
    user.api_access_tokens.first.update(deleted_at: Time.now)
    expect(described_class.find_by_access_token(token)).to be_nil
  end

  it "works if it cannot find user by access token" do
    missing_user = described_class.find_by_access_token("junk_token")
    expect(missing_user).to be_nil
  end

  it "rejects an access token once it has expired" do
    user = create(:user, is_service_account: true)
    token = user.api_access_tokens.create!(expires_at: 1.hour.from_now)

    expect(described_class.find_by_access_token(token.access_token)).to eq(user)
    travel 2.hours do
      expect(described_class.find_by_access_token(token.access_token)).to be_nil
    end
  end

  describe ".signing_token_for_agency" do
    let(:first_account) { create(:user, client_agency_id: "sandbox", is_service_account: true) }
    let(:second_account) { create(:user, client_agency_id: "sandbox", is_service_account: true) }

    it "is the oldest active token across all of the partner's service accounts" do
      first_account.api_access_tokens.create!(created_at: 2.days.ago)
      oldest = second_account.api_access_tokens.create!(created_at: 3.days.ago)

      expect(described_class.signing_token_for_agency("sandbox")).to eq(oldest)
      expect(described_class.api_key_for_agency("sandbox")).to eq(oldest.access_token)
    end

    it "skips expired and revoked tokens, however old" do
      first_account.api_access_tokens.create!(created_at: 5.days.ago, expires_at: 1.minute.ago)
      first_account.api_access_tokens.create!(created_at: 4.days.ago, deleted_at: 1.day.ago)
      expiring = first_account.api_access_tokens.create!(created_at: 3.days.ago, expires_at: 1.hour.from_now)
      newest = first_account.api_access_tokens.create!(created_at: 1.day.ago)

      expect(described_class.signing_token_for_agency("sandbox")).to eq(expiring)
      travel 2.hours do
        expect(described_class.signing_token_for_agency("sandbox")).to eq(newest)
      end
    end

    it "ignores tokens of users that aren't service accounts, and other partners" do
      create(:user, client_agency_id: "sandbox").api_access_tokens.create!(created_at: 9.days.ago)
      create(:user, client_agency_id: "other", is_service_account: true).api_access_tokens.create!(created_at: 9.days.ago)
      token = first_account.api_access_tokens.create!

      expect(described_class.signing_token_for_agency("sandbox")).to eq(token)
    end

    it "is nil when the partner has no active token" do
      first_account.api_access_tokens.create!(expires_at: 1.minute.ago)

      expect(described_class.signing_token_for_agency("sandbox")).to be_nil
    end
  end
end
