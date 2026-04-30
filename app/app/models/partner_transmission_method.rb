class PartnerTransmissionMethod < ApplicationRecord
  belongs_to :partner_config
  has_many :partner_transmission_configs, dependent: :destroy

  enum :method_type, { sftp: 0, shared_email: 1, encrypted_s3: 2, json: 3, webhook: 4 }

  validates :method_type, presence: true
end
