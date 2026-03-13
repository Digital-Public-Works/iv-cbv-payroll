class PartnerConfig < ApplicationRecord
  has_many :partner_transmission_configs, dependent: :destroy
  has_many :partner_application_attributes, dependent: :destroy

  validates :partner_id, uniqueness: true

  enum :transmission_method, [ :sftp, :shared_email, :encrypted_s3, :json ]
end
