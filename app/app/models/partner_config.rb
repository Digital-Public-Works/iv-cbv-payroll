class PartnerConfig < ApplicationRecord
  has_many :partner_transmission_methods, dependent: :destroy
  has_many :partner_transmission_configs, dependent: :destroy
  has_many :partner_application_attributes, dependent: :destroy
  has_many :partner_translations, dependent: :destroy

  validates :partner_id, uniqueness: true

  # TODO: remove after migration 20260406000000_create_partner_transmission_methods
  # has been applied in all environments. Kept only so the migration's data-copy
  # SQL can reference the old integer column before it is dropped.
  begin
    if ActiveRecord::Base.connection.column_exists?(:partner_configs, :transmission_method)
      enum :transmission_method, { sftp: 0, shared_email: 1, encrypted_s3: 2, json: 3, webhook: 4 }
    end
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    # DB not available yet (e.g. during asset precompilation)
  end
end
