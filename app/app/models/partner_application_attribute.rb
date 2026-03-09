class PartnerApplicationAttribute < ApplicationRecord
  belongs_to :partner_config

  enum :data_type, [ :string, :integer, :float ]
end
