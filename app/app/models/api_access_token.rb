class ApiAccessToken < ApplicationRecord
  belongs_to :user

  encrypts :access_token, deterministic: true

  # not revoked or expired
  scope :active, -> {
    where(deleted_at: nil).where("api_access_tokens.expires_at IS NULL OR api_access_tokens.expires_at > ?", Time.current)
  }

  before_create do
    self.access_token = SecureRandom.alphanumeric(32)
  end

  def active?
    deleted_at.nil? && (expires_at.nil? || expires_at.future?)
  end
end
