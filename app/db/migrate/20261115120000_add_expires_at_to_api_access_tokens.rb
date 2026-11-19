# Lets an invitation API token expire (e.g. the old token after a rotation).
# Null means no expiry. Expired tokens are kept for auditability.
class AddExpiresAtToApiAccessTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :api_access_tokens, :expires_at, :datetime
  end
end
