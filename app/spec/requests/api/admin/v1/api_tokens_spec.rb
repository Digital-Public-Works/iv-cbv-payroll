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

    it "refuses when the partner has an active token without an expiry" do
      service_user.api_access_tokens.create!

      expect { admin_request(:post, base) }.not_to change(ApiAccessToken, :count)

      expect(response).to have_http_status(:conflict)
      expect(json_body["message"]).to include("rotate it instead")
    end

    it "creates a new token when the partner's only active token is expiring, leaving that one as is" do
      at = 1.day.from_now.change(usec: 0)
      expiring = service_user.api_access_tokens.create!(expires_at: at)

      expect { admin_request(:post, base) }.to change(ApiAccessToken, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(active_count).to eq(2)
      expect(expiring.reload.expires_at).to eq(at)
    end

    it "refuses when the partner has two expiring tokens" do
      2.times { service_user.api_access_tokens.create!(expires_at: 1.day.from_now) }

      expect { admin_request(:post, base) }.not_to change(ApiAccessToken, :count)

      expect(response).to have_http_status(:conflict)
      expect(json_body["message"]).to include("expire the extra ones")
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

    it "refuses to rotate a token that isn't the partner's newest" do
      admin_request(:post, "#{base}/#{old.id}/rotate")

      expect { admin_request(:post, "#{base}/#{old.id}/rotate") }.not_to change(ApiAccessToken, :count)

      expect(response).to have_http_status(:conflict)
      expect(json_body["message"]).to include("only the newest can be rotated")
    end

    it "ends the expiring token immediately when the new one is rotated during its grace period" do
      admin_request(:post, "#{base}/#{old.id}/rotate")
      middle = ApiAccessToken.last

      admin_request(:post, "#{base}/#{middle.id}/rotate")

      expect(response).to have_http_status(:created)
      newest = ApiAccessToken.last
      expect(old.reload.active?).to be(false)
      expect(User.find_by_access_token(old.access_token)).to be_nil
      expect(middle.reload.expires_at).to be_within(1.minute).of(48.hours.from_now)
      expect(active_count).to eq(2)
      expect(User.signing_token_for_agency("admin_spec")).to eq(middle)
      expect(User.find_by_access_token(newest.access_token)).to eq(service_user)
    end

    it "rotates the partner's only token when it is already expiring, keeping its expiry" do
      at = 2.days.from_now.change(usec: 0)
      old.update!(expires_at: at)

      expect { admin_request(:post, "#{base}/#{old.id}/rotate") }.to change(ApiAccessToken, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json_body["api_token"]).to include("status" => "active")
      expect(old.reload.expires_at).to eq(at)
    end

    it "uses the given expiry when rotating an already expiring token" do
      old.update!(expires_at: 2.days.from_now)
      at = 5.hours.from_now.change(usec: 0)

      admin_request(:post, "#{base}/#{old.id}/rotate", body: { expires_at: at.utc.iso8601 })

      expect(response).to have_http_status(:created)
      expect(old.reload.expires_at).to eq(at)
    end

    it "ends the older expiring token when the newest is also expiring and there's no new one" do
      newer = service_user.api_access_tokens.create!(expires_at: 2.days.from_now)
      old.update!(expires_at: 1.day.from_now)

      admin_request(:post, "#{base}/#{newer.id}/rotate")

      expect(response).to have_http_status(:created)
      expect(old.reload.active?).to be(false)
      expect(active_count).to eq(2)
    end

    it "refuses to rotate an expiring token when the partner already has one without an expiry" do
      newer = service_user.api_access_tokens.create!(expires_at: 2.days.from_now)

      expect { admin_request(:post, "#{base}/#{newer.id}/rotate") }.not_to change(ApiAccessToken, :count)

      expect(response).to have_http_status(:conflict)
      expect(json_body["message"]).to include("already has an API token without an expiry")
      expect(old.reload.expires_at).to be_nil
    end

    it "refuses for a partner with two tokens without an expiry, ending neither" do
      newer = service_user.api_access_tokens.create!

      expect { admin_request(:post, "#{base}/#{newer.id}/rotate") }.not_to change(ApiAccessToken, :count)

      expect(response).to have_http_status(:conflict)
      expect(json_body["message"]).to include("expire the extra ones")
      expect(active_count).to eq(2)
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

  describe "isolation between partners" do
    let(:other_user) { User.create!(email: "ffs-eng+other@digitalpublicworks.org", client_agency_id: "other", is_service_account: true) }
    # Newer than any admin_spec token, and in every state the rules look at
    # (expiring, without an expiry), so a missing partner scope would change
    # which token counts as newest, oldest or "new" for admin_spec.
    let!(:other_tokens) do
      [
        other_user.api_access_tokens.create!(created_at: 3.days.ago, expires_at: 1.day.from_now),
        other_user.api_access_tokens.create!(created_at: 1.minute.from_now)
      ]
    end

    def other_snapshot
      ApiAccessToken.where(user: other_user).order(:id).pluck(:id, :access_token, :expires_at, :deleted_at, :updated_at)
    end

    def expect_other_partner_untouched
      before = other_snapshot
      yield
      expect(other_snapshot).to eq(before)
    end

    it "create ignores the other partner's tokens and leaves them alone" do
      service_user
      expect_other_partner_untouched { admin_request(:post, base) }

      expect(response).to have_http_status(:created)
      expect(ApiAccessToken.last.user).to eq(service_user)
    end

    it "rotate counts only this partner's tokens as newest and leaves the other partner's alone" do
      token = service_user.api_access_tokens.create!(created_at: 1.day.ago)

      expect_other_partner_untouched { admin_request(:post, "#{base}/#{token.id}/rotate") }

      expect(response).to have_http_status(:created)
    end

    it "rotate only ends this partner's expiring token to make room" do
      old = service_user.api_access_tokens.create!(created_at: 2.days.ago)
      admin_request(:post, "#{base}/#{old.id}/rotate")
      middle = ApiAccessToken.last

      expect_other_partner_untouched { admin_request(:post, "#{base}/#{middle.id}/rotate") }

      expect(response).to have_http_status(:created)
      expect(old.reload.active?).to be(false)
    end

    it "rotate of an expiring token isn't blocked by the other partner's token without an expiry" do
      token = service_user.api_access_tokens.create!(expires_at: 1.day.from_now)

      expect_other_partner_untouched { admin_request(:post, "#{base}/#{token.id}/rotate") }

      expect(response).to have_http_status(:created)
    end

    it "refuses every change to the other partner's token through this partner's routes" do
      target = other_tokens.last
      at = 2.days.from_now.utc.iso8601

      expect_other_partner_untouched do
        admin_request(:post, "#{base}/#{target.id}/rotate")
        expect(response).to have_http_status(:not_found)
        admin_request(:put, "#{base}/#{target.id}/expiry", body: { expires_at: at })
        expect(response).to have_http_status(:not_found)
        admin_request(:post, "#{base}/#{target.id}/expire")
        expect(response).to have_http_status(:not_found)
      end
      expect(ApiAccessToken.where(user: service_user)).to be_empty
    end

    it "set expiry and expire on this partner's token leave the other partner's alone" do
      token = service_user.api_access_tokens.create!

      expect_other_partner_untouched do
        admin_request(:put, "#{base}/#{token.id}/expiry", body: { expires_at: 2.days.from_now.utc.iso8601 })
        expect(response).to have_http_status(:ok)
        admin_request(:post, "#{base}/#{token.id}/expire")
        expect(response).to have_http_status(:ok)
      end
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
