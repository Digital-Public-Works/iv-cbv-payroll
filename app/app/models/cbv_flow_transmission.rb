class CbvFlowTransmission < ApplicationRecord
  belongs_to :cbv_flow

  enum :method_type, Transmitters::TransmissionMethodTypes::METHOD_TYPES

  enum :status, {
    pending: 0,
    succeeded: 1,
    failed: 2
  }

  validates :method_type, presence: true, uniqueness: { scope: :cbv_flow_id }
end
