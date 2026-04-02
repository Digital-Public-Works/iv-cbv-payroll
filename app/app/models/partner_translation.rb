class PartnerTranslation < ApplicationRecord
  belongs_to :partner_config

  validates :locale, presence: true
  validates :key, presence: true, uniqueness: { scope: [ :partner_config_id, :locale ] }
  validates :value, presence: true
end
