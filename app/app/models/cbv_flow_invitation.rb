class CbvFlowInvitation < ApplicationRecord
  # We're opting not to use URI::MailTo::EMAIL_REGEXP
  # https://html.spec.whatwg.org/multipage/input.html#valid-e-mail-address
  #
  # EXCERPT: This requirement is a willful violation of RFC 5322, which defines a syntax for email addresses
  # that is simultaneously too strict (before the "@" character), too vague (after the "@" character),
  # and too lax (allowing comments, whitespace characters, and quoted strings in manners unfamiliar to most users)
  # to be of practical use here.
  EMAIL_REGEX = /\A[\w+\-](?:[^\w+\-]?[\w+\-])*[^\w+\-]?@[a-z\d\-]+(?:\.[a-z\d\-]+)*\.[a-z\d\-]+\z/i

  # E.164-normalized NANP number: +1, then a valid area code and exchange.
  US_PHONE_REGEX = /\A\+1[2-9]\d{2}[2-9]\d{6}\z/

  MAX_FLOWS_PER_INVITATION = 100

  VALID_LOCALES = Rails.application.config.i18n.available_locales.map(&:to_s).freeze

  # How the invitation is communicated to the applicant. Determines which
  # contact fields are required. "link" means no send: the caller copies the
  # tokenized URL. Defaults to "email" so callers that predate channels (the
  # API) keep requiring an email address.
  COMMUNICATION_CHANNELS = %w[email sms link].freeze

  attr_accessor :expiration_days, :expiration_date

  attribute :communication_channel, :string, default: "email"

  belongs_to :user
  belongs_to :cbv_applicant, optional: true
  has_many :cbv_flows
  has_many :invitation_communications, dependent: :destroy

  has_secure_token :auth_token, length: 10

  accepts_nested_attributes_for :cbv_applicant

  before_create :set_expires_at, if: :new_record?
  before_validation :normalize_language
  before_validation :normalize_communication_channel
  before_validation :normalize_phone_number

  validates :client_agency_id, inclusion: { in: ->(_) { ClientAgencyConfig.instance.client_agency_ids } }
  validates :communication_channel, inclusion: { in: COMMUNICATION_CHANNELS }
  validates :email_address, presence: true, if: :email_communication_channel?
  validates :email_address, format: { with: EMAIL_REGEX, message: :invalid_format }, allow_blank: true
  validates :phone_number, presence: true, if: :sms_communication_channel?
  validates :phone_number, format: { with: US_PHONE_REGEX, message: :invalid_format }, allow_blank: true
  validates_associated :cbv_applicant
  validates :language, inclusion: {
    in: VALID_LOCALES,
    message: :invalid_format,
    case_sensitive: false
  }
  validate :applicant_information, :validate_expiration_params
  validates :expiration_days,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 },
            allow_nil: true

  include Redactable
  has_redactable_fields(
    email_address: :email,
    phone_number: :string,
    auth_token: :string
  )

  scope :unstarted, -> { left_outer_joins(:cbv_flows).where(cbv_flows: { id: nil }) }

  def expires_at_local
    expires_at&.in_time_zone(agency_time_zone)
  end

  def expired?
    Time.current.after?(expires_at) || redacted_at?
  end

  def complete?
    cbv_flows.any?(&:complete?)
  end

  def at_flow_limit?
    cbv_flows.count >= MAX_FLOWS_PER_INVITATION
  end

  def to_url(origin: nil)
    client_agency = ClientAgencyConfig.instance[client_agency_id]
    raise ArgumentError.new("Client Agency #{client_agency_id} not found") unless client_agency

    url_params = {
      token: auth_token,
      locale: language,
      host: client_agency.agency_domain + "." + ENV["DOMAIN_NAME"],
      protocol: (client_agency.agency_domain.nil? || Rails.env == "development") ? "http" : "https"
    }
    url_params[:origin] = origin if origin.present?

    url = Rails.application.routes.url_helpers.start_flow_url(url_params.compact)
    # safe add of '?' at the end of the URL for partners adding the &origin param.
    url.include?("?") ? url : "#{url}?"
  end

  def normalize_language
    self.language = language.to_s.downcase if language.present?
  end

  def normalize_communication_channel
    self.communication_channel = communication_channel.to_s.presence || "email"
  end

  # Normalizes user-entered US phone numbers ("(555) 234-5678", "1-555-234-5678")
  # to E.164 (+15552345678). Invalid input is left for the format validation.
  def normalize_phone_number
    return if phone_number.blank?

    digits = phone_number.gsub(/\D/, "")
    digits = digits.delete_prefix("1") if digits.length == 11
    self.phone_number = "+1#{digits}"
  end

  def email_communication_channel?
    communication_channel == "email"
  end

  def sms_communication_channel?
    communication_channel == "sms"
  end

  def phone_number_last_4
    phone_number&.last(4)
  end

  def applicant_information
    return unless cbv_applicant.present?

    cbv_applicant.required_applicant_attributes.each do |attr|
      next if cbv_applicant.send(attr).present?

      errors.add(
        :"cbv_applicant.#{attr}",
        I18n.t(
          "activerecord.errors.models.cbv_applicant.attributes.#{attr}.blank",
          default: "is required"
        )
      )
    end
  end

  def validate_expiration_params
    if expiration_days.present? && expiration_date.present?
      errors.add(:base, "Provide either expiration_days or expiration_date, but not both.")
      return
    end

    if expiration_date.present?
      begin
        parsed_date = Time.iso8601(expiration_date.to_s)

        if parsed_date < Time.current
          errors.add(:expiration_date, "cannot be in the past")
        elsif parsed_date > 1.year.from_now
          errors.add(:expiration_date, "cannot be more than 1 year in the future")
        end
      rescue ArgumentError
        errors.add(:expiration_date, "must be a full ISO8601 datetime with a timezone")
      end
      return
    end

    # expiration_days is also validated using a numericality validator above
    if expiration_days.present? && (Time.current + expiration_days.to_i.days) > 1.year.from_now
      errors.add(:expiration_days, "cannot be more than 1 year in the future")
    end
  end

  private
  def set_expires_at
    self.expires_at ||= calculate_expires_at
  end

  def calculate_expires_at
    Time.use_zone(agency_config.timezone) do
      if expiration_date.present?
        Time.zone.parse(expiration_date)
      elsif expiration_days.present?
        (created_at || Time.current).end_of_day + expiration_days.to_i.days
      else
        (created_at || Time.current).end_of_day + agency_config.invitation_valid_days.days
      end
    end
  end

  def agency_config
    ClientAgencyConfig.instance[client_agency_id]
  end

  def agency_time_zone
    agency_config.timezone
  end
end
