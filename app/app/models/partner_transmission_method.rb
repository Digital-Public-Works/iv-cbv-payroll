class PartnerTransmissionMethod < ApplicationRecord
  include TransmissionMethodTypes

  belongs_to :partner_config
  has_many :partner_transmission_configs, dependent: :destroy

  validates :method_type, presence: true
end
