class CbvFlowTransmissionAttempt < ApplicationRecord
  belongs_to :cbv_flow_transmission

  enum :method_type, {
    sftp: 0,
    shared_email: 1,
    encrypted_s3: 2,
    json: 3,
    webhook: 4
  }

  enum :status, {
    pending: 0,
    processing: 1,
    succeeded: 2,
    failed: 3
  }

  validates :method_type, presence: true
  validates :method_type, uniqueness: { scope: :cbv_flow_transmission_id }
end
