class PartnerConfig < ApplicationRecord
  has_many :partner_transmission_methods, dependent: :destroy
  has_many :partner_transmission_configs, dependent: :destroy
  has_many :partner_application_attributes, dependent: :destroy
  has_many :partner_translations, dependent: :destroy

  validates :partner_id, uniqueness: true
end
