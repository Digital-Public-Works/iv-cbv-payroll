class PartnerApplicationAttribute < ApplicationRecord
  belongs_to :partner_config

  validates :name, presence: true, uniqueness:
    { scope: :partner_config_id,
      message: "should be unique per partner" }


  enum :data_type, [ :string, :integer, :float ]
end
