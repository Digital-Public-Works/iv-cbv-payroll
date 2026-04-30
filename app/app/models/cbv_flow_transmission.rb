class CbvFlowTransmission < ApplicationRecord
  belongs_to :cbv_flow

  enum :method_type, {
    sftp: 0,
    shared_email: 1,
    encrypted_s3: 2,
    json: 3,
    webhook: 4
  }

  enum :status, {
    pending: 0,
    succeeded: 1,
    failed: 2
  }

  validates :method_type, presence: true, uniqueness: { scope: :cbv_flow_id }
end
