class PartnerTransmissionConfig < ApplicationRecord
  belongs_to :partner_config

  validates :key, presence: true

  def value=(val)
    if is_encrypted? && val
      self[:value] = encrypt_value(val)
    else
      self[:value] = val
    end
  end

  def value
    val = self[:value]
    return val if val.blank?

    begin
      decrypt_value(val)
    rescue ActiveRecord::Encryption::Errors::Decryption
      val
    end
  end

  private

  def encrypt_value(val)
    ActiveRecord::Encryption::Encryptor.new.encrypt(val)
  end

  def decrypt_value(val)
    ActiveRecord::Encryption::Encryptor.new.decrypt(val)
  end
end
