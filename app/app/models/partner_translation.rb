class PartnerTranslation < ApplicationRecord
  belongs_to :partner_config

  validates :locale, presence: true
  validates :key, presence: true, uniqueness: { scope: [ :partner_config_id, :locale ] }
  validates :value, presence: true

  after_save :expire_cache
  after_destroy :expire_cache

  def self.cache_key_for(partner_id, locale, translation_key)
    "partner_translation/#{partner_id}/#{locale}/#{translation_key}"
  end

  private

  def expire_cache
    Rails.cache.delete(self.class.cache_key_for(partner_config.partner_id, locale, key))
  end
end
