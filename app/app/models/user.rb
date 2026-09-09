class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :rememberable, :trackable, :timeoutable

  # Owner of invitations created through the /admin portal before real admin
  # identities exist (see ADR-0002). One per agency, since email uniqueness is
  # scoped by client_agency_id.
  ADMIN_SYSTEM_USER_EMAIL = "platform-admin-system@digitalpublicworks.org".freeze

  has_many :api_access_tokens, dependent: :destroy

  def self.admin_system_user_for(client_agency_id)
    find_or_create_by!(email: ADMIN_SYSTEM_USER_EMAIL, client_agency_id: client_agency_id) do |user|
      user.is_service_account = true
    end
  end

  def self.find_by_access_token(token)
    token_user = ApiAccessToken.find_by(access_token: token, deleted_at: nil)&.user

    token_user if token_user && token_user.is_service_account
  end

  def self.api_key_for_agency(agency_id)
    user = find_by(client_agency_id: agency_id, is_service_account: true)
    return nil unless user

    oldest_token = user.api_access_tokens
      .where(deleted_at: nil)
      .order(:created_at)
      .first

    oldest_token&.access_token
  end
end
