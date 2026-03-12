class PartnerTransmissionConfig < ApplicationRecord
  belongs_to :partner_config

  validates :key, presence: true, uniqueness:
    { scope: :partner_id,
      message: "should be unique per partner" }
end
