class PartnerTransmissionMethod < ApplicationRecord
  belongs_to :partner_config
  has_many :partner_transmission_configs, dependent: :destroy

  enum :method_type, TransmissionMethodTypes::METHOD_TYPES

  validates :method_type, presence: true
end
