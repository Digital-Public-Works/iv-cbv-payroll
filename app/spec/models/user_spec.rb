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

  describe ".admin_system_user_for" do
    it "creates one service-account user per agency and reuses it" do
      user = described_class.admin_system_user_for("sandbox")

      expect(user.is_service_account).to be(true)
      expect(user.client_agency_id).to eq("sandbox")
      expect(described_class.admin_system_user_for("sandbox").id).to eq(user.id)
    end

    it "keeps system users separate across agencies" do
      sandbox_user = described_class.admin_system_user_for("sandbox")
      other_user = described_class.admin_system_user_for("az_des")

      expect(other_user.id).not_to eq(sandbox_user.id)
      expect(other_user.email).to eq(sandbox_user.email)
    end
  end
end
