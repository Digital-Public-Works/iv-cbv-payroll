class PartnerConfig < ApplicationRecord
  has_many :partner_transmission_configs, dependent: :destroy
  has_many :partner_application_attributes, dependent: :destroy
  has_one :partner_output_configuration, dependent: :destroy
  has_many :partner_translations, dependent: :destroy

  validates :partner_id, uniqueness: true

  enum :transmission_method, { sftp: 0, shared_email: 1, encrypted_s3: 2, json: 3 }
end
