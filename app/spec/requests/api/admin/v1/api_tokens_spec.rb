require "rails_helper"

RSpec.describe "Admin API: invitation API tokens", type: :request do
  # Tokens are credentials: managed in prod too, where settings are read-only.
  around { |example| with_admin_api(settings_writable: false) { example.run } }

  before { create_admin_partner! }

  let(:base) { "/api/admin/v1/partners/admin_spec/api_tokens" }
  let(:service_user) do
    User.create!(email: "ffs-eng+admin_spec@digitalpublicworks.org", client_agency_id: "admin_spec", is_service_account: true)
  end

  def active_count = ApiAccessToken.active.where(user: service_user).count

  describe "GET index" do
    it "lists active tokens oldest first, then ended ones, without their values" do
      older = service_user.api_access_tokens.create!(created_at: 3.days.ago)
      expiring = service_user.api_access_tokens.create!(created_at: 2.days.ago, expires_at: 1.day.from_now)
      expired = service_user.api_access_tokens.create!(created_at: 5.days.ago, expires_at: 1.hour.ago)
      revoked = service_user.api_access_tokens.create!(created_at: 6.days.ago, deleted_at: 2.days.ago)
      other = User.create!(email: "x@example.org", client_agency_id: "other", is_service_account: true)
      other.api_access_tokens.create!

      admin_request(:get, base)

      expect(response).to have_http_status(:ok)
      tokens = json_body["api_tokens"]
      expect(tokens.map { |t| [ t["id"], t["status"] ] }).to eq([
        [ older.id, "active" ], [ expiring.id, "expiring" ], [ expired.id, "expired" ], [ revoked.id, "revoked" ]
      ])
      expect(tokens.first).to include("user_email" => service_user.email, "last_four" => older.access_token.last(4),
                                      "json_signing_key" => true, "expires_at" => nil)
      expect(tokens.second["expires_at"]).to eq(expiring.expires_at.iso8601(3))
      expect(tokens.fourth["revoked_at"]).to eq(revoked.deleted_at.iso8601(3))
      expect(tokens.drop(1).pluck("json_signing_key")).to all(be(false))
      [ older, expiring, expired, revoked ].each { |t| expect(response.body).not_to include(t.access_token) }
    end

    it "ignores tokens of users that aren't service accounts" do
      User.create!(email: "person@example.org", client_agency_id: "admin_spec").api_access_tokens.create!

      admin_request(:get, base)

      expect(json_body["api_tokens"]).to eq([])
    end

    it "returns 404 for an unknown partner" do
      admin_request(:get, "/api/admin/v1/partners/nope/api_tokens")

      expect(response).to have_http_status(:not_found)
    end

    it "refuses unsigned requests" do
      get base

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST create" do
    it "creates the service account when there is none and returns the value once" do
      expect { admin_request(:post, base) }.to change(ApiAccessToken, :count).by(1)

      expect(response).to have_http_status(:created)
      token = ApiAccessToken.last
      expect(json_body["api_token"]).to include("id" => token.id, "access_token" => token.access_token, "json_signing_key" => true)
      expect(token.user).to have_attributes(client_agency_id: "admin_spec", is_service_account: true,
                                             email: "ffs-eng+admin_spec@digitalpublicworks.org")
      expect(User.find_by_access_token(token.access_token)).to eq(token.user)
    end

    it "uses the existing service account when its tokens have all ended" do
      service_user.api_access_tokens.create!(expires_at: 1.minute.ago)

      expect { admin_request(:post, base) }.not_to change(User, :count)

      expect(response).to have_http_status(:created)
      expect(active_count).to eq(1)
    end

    it "refuses when the partner has an active token" do
      service_user.api_access_tokens.create!(expires_at: 1.day.from_now)

      expect { admin_request(:post, base) }.not_to change(ApiAccessToken, :count)

      expect(response).to have_http_status(:conflict)
      expect(json_body["message"]).to include("rotate it instead")
    end
  end

  describe "POST rotate" do
    let!(:old) { service_user.api_access_tokens.create!(created_at: 1.day.ago) }

    it "creates a new token and gives the old one a 48 hour grace period by default" do
      admin_request(:post, "#{base}/#{old.id}/rotate")

      expect(response).to have_http_status(:created)
      new_token = ApiAccessToken.last
      expect(json_body["api_token"]).to include("id" => new_token.id, "access_token" => new_token.access_token,
                                                "status" => "active", "json_signing_key" => false)
      expect(new_token.user).to eq(service_user)
      expect(old.reload.expires_at).to be_within(1.minute).of(48.hours.from_now)
      # Both authenticate during the grace period; the old one still signs.
      expect(User.find_by_access_token(old.access_token)).to eq(service_user)
      expect(User.find_by_access_token(new_token.access_token)).to eq(service_user)
      expect(User.signing_token_for_agency("admin_spec")).to eq(old)
    end

    it "uses the given expiry" do
      at = 3.days.from_now.change(usec: 0)

      admin_request(:post, "#{base}/#{old.id}/rotate", body: { expires_at: at.utc.iso8601 })

      expect(response).to have_http_status(:created)
      expect(old.reload.expires_at).to eq(at)
    end

    it "hands authentication and signing to the new token once the old one expires" do
      admin_request(:post, "#{base}/#{old.id}/rotate", body: { expires_at: 1.hour.from_now.utc.iso8601 })
      new_token = ApiAccessToken.last

      travel 2.hours do
        expect(User.find_by_access_token(old.access_token)).to be_nil
        expect(User.signing_token_for_agency("admin_spec")).to eq(new_token)
      end
    end

    it "refuses an expiry in the past or more than 30 days away, changing nothing" do
      [ 1.minute.ago, 31.days.from_now ].each do |at|
        expect { admin_request(:post, "#{base}/#{old.id}/rotate", body: { expires_at: at.utc.iso8601 }) }
          .not_to change(ApiAccessToken, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(old.reload.expires_at).to be_nil
      end
    end

    it "refuses an unparseable expiry" do
      admin_request(:post, "#{base}/#{old.id}/rotate", body: { expires_at: "tomorrow" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body["message"]).to include("ISO 8601")
    end

    it "refuses while a rotation is in progress" do
      admin_request(:post, "#{base}/#{old.id}/rotate")
      new_token = ApiAccessToken.last

      expect { admin_request(:post, "#{base}/#{new_token.id}/rotate") }.not_to change(ApiAccessToken, :count)
      expect(response).to have_http_status(:conflict)

      admin_request(:post, "#{base}/#{old.id}/rotate")
      expect(response).to have_http_status(:conflict)
      expect(json_body["message"]).to include("already expiring")
    end

    it "refuses for a partner with two tokens without an expiry" do
      service_user.api_access_tokens.create!

      admin_request(:post, "#{base}/#{old.id}/rotate")

      expect(response).to have_http_status(:conflict)
      expect(json_body["message"]).to include("expire the extra ones")
    end
  end

  describe "PUT expiry" do
    let!(:token) { service_user.api_access_tokens.create!(expires_at: 1.day.from_now) }

    it "changes the expiry" do
      at = 10.days.from_now.change(usec: 0)

      admin_request(:put, "#{base}/#{token.id}/expiry", body: { expires_at: at.utc.iso8601 })

      expect(response).to have_http_status(:ok)
      expect(token.reload.expires_at).to eq(at)
      expect(json_body["api_tokens"].first["expires_at"]).to eq(at.iso8601(3))
    end

    it "requires an expiry" do
      admin_request(:put, "#{base}/#{token.id}/expiry", body: {})

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST expire" do
    it "ends the token immediately and keeps it listed" do
      token = service_user.api_access_tokens.create!(expires_at: 2.days.from_now)

      admin_request(:post, "#{base}/#{token.id}/expire")

      expect(response).to have_http_status(:ok)
      expect(User.find_by_access_token(token.access_token)).to be_nil
      expect(json_body["api_tokens"]).to contain_exactly(include("id" => token.id, "status" => "expired"))
    end

    it "returns 404 for a token that has already ended" do
      token = service_user.api_access_tokens.create!(deleted_at: Time.current)

      admin_request(:post, "#{base}/#{token.id}/expire")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET reveal" do
    it "returns the token value" do
      token = service_user.api_access_tokens.create!

      admin_request(:get, "#{base}/#{token.id}/reveal")

      expect(response).to have_http_status(:ok)
      expect(json_body).to eq("access_token" => token.access_token)
    end

    it "does not reveal another partner's token" do
      token = User.create!(email: "x@example.org", client_agency_id: "other", is_service_account: true).api_access_tokens.create!

      admin_request(:get, "#{base}/#{token.id}/reveal")

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(token.access_token)
    end

    it "does not reveal an expired token" do
      token = service_user.api_access_tokens.create!(expires_at: 1.minute.ago)

      admin_request(:get, "#{base}/#{token.id}/reveal")

      expect(response).to have_http_status(:not_found)
    end
  end
end
