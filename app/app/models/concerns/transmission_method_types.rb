module TransmissionMethodTypes
  extend ActiveSupport::Concern

  METHOD_TYPES = {
    sftp: 0,
    shared_email: 1,
    encrypted_s3: 2,
    json: 3,
    webhook: 4
  }.freeze

  included do
    enum :method_type, METHOD_TYPES
  end
end
