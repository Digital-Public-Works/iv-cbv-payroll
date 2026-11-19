class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :rememberable, :trackable, :timeoutable

  has_many :api_access_tokens, dependent: :destroy

  def self.find_by_access_token(token)
    token_user = ApiAccessToken.active.find_by(access_token: token)&.user

    token_user if token_user && token_user.is_service_account
  end

  # placeholder account that is the 'creator' of auto-generated invitations for generic flow
  SYSTEM_ACCOUNT_EMAIL_DOMAIN = "system.verifymyincome.org".freeze

  def self.system_account_for(client_agency_id)
    raise ArgumentError, "client_agency_id is required" if client_agency_id.blank?

    attrs = { client_agency_id: client_agency_id, email: system_account_email_for(client_agency_id) }

    find_or_create_by!(**attrs) { |user| user.is_service_account = false }
  rescue ActiveRecord::RecordNotUnique
    # Two generic-link visits can race to create it; the unique index settles it.
    find_by!(**attrs)
  end

  def self.system_account_email_for(client_agency_id)
    "auto-invitation+#{client_agency_id}@#{SYSTEM_ACCOUNT_EMAIL_DOMAIN}"
  end

  def system_account?
    email == self.class.system_account_email_for(client_agency_id)
  end

  def self.api_key_for_agency(agency_id)
    signing_token_for_agency(agency_id)&.access_token
  end

  # oldes token is the one used for signing, when it expires, new active token is used for signing
  def self.signing_token_for_agency(agency_id)
    ApiAccessToken.active
      .joins(:user)
      .where(users: { client_agency_id: agency_id, is_service_account: true })
      .order(:created_at, :id)
      .first
  end
end
