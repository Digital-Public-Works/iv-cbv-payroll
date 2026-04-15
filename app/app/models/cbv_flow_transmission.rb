class CbvFlowTransmission < ApplicationRecord
  belongs_to :cbv_flow
  has_many :cbv_flow_transmission_attempts, dependent: :destroy

  enum :status, {
    pending: 0,
    completed: 1,
    failed: 2
  }

  validates :cbv_flow_id, uniqueness: true
end
