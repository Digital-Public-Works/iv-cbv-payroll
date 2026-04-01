class CbvApplicant < ApplicationRecord
  include Redactable

  after_initialize :set_snap_application_date, if: :new_record?
  after_initialize :set_applicant_attributes
  attr_reader :applicant_attributes, :required_applicant_attributes

  def self.valid_attributes_for_agency(client_agency_id)
    agency = ClientAgencyConfig.instance[client_agency_id]
    agency.applicant_attributes.keys.map(&:to_sym)
  end

  def self.build_agency_partner_metadata(client_agency_id, &value_provider)
    valid_attributes_for_agency(client_agency_id).each_with_object({}) do |attr, hash|
      hash[attr.to_s] = value_provider.call(attr)
    end
  end

  has_many :cbv_flows
  has_many :cbv_flow_invitations

  validates :client_agency_id, presence: true

  # validate that the date_of_birth is in the past
  validates :date_of_birth, comparison: {
    less_than_or_equal_to: Date.current,
     message: :future_date
  }, if: -> { is_applicant_attribute_required?(:date_of_birth) && date_of_birth.present? }

  # validate that the date_of_birth is not more than 110 years ago
  validates :date_of_birth, comparison: {
    greater_than_or_equal_to: 110.years.ago.to_date,
    message: :invalid_date
  }, if: -> { is_applicant_attribute_required?(:date_of_birth) && date_of_birth.present? }

  validates :snap_application_date, presence: {
    message: :invalid_date
  }

  def agency_expected_names
    return [] if redacted_at?
    return [] unless income_changes.present?

    Array(income_changes).map { |c| c["member_name"] }.uniq
  end

  def redact!(fields = nil)
    fields_to_redact = fields || redactable_fields_from_config
    raise "No fields to redact for #{client_agency_id}" unless fields_to_redact.present?

    fields_to_redact.each do |field, type|
      self[field] = Redactable::REDACTION_REPLACEMENTS[type]
    end

    if income_changes.present?
      self[:income_changes] = redact_member_names_in_json(income_changes)
    end

    self[Redactable::REDACTED_TIMESTAMP_COLUMN] = Time.now
    save(validate: false)
  end

  def date_of_birth=(value)
    if value.is_a?(Hash)
      day = value["day"].to_i
      month = value["month"].to_i
      year = value["year"].to_i
      self[:date_of_birth] = Date.new(year, month, day) rescue nil
    else
      self[:date_of_birth] = parse_date(value)
    end
  end

  def snap_application_date=(value)
    self[:snap_application_date] = parse_date(value)
  end

  def has_applicant_attribute_missing?
    @required_applicant_attributes.any? do |attr|
      self[attr].nil?
    end
  end

  def validate_base_and_applicant_attributes?
    valid? && validate_required_applicant_attributes.empty?
  end

  def validate_required_applicant_attributes
    missing_attrs = @required_applicant_attributes.reject do |attr|
      self.send(attr).present?
    end

    if missing_attrs.any?
      missing_attrs.each do |attr|
        errors.add(attr, I18n.t("cbv.applicant_informations.#{client_agency_id}.fields.#{attr}.blank",
          default: I18n.t("cbv.applicant_informations.default.fields.#{attr}.blank", default: "is required")))
      end
    end

    missing_attrs
  end

  def set_snap_application_date
    self.snap_application_date ||= Date.current
  end

  def set_applicant_attributes
    @applicant_attributes = agency_config&.applicant_attributes&.compact&.keys&.map(&:to_sym) || []

    @required_applicant_attributes = get_required_applicant_attributes
  end

  # Reset the applicant attributes to nil by removing any non-symbol keys i.e. { date_of_birth: [ :day, :month, :year ] }
  # and then setting the attributes to nil.
  # Need to skip snap_application_date because this class has a vlaidation on it.
  def reset_applicant_attributes
    clear_attributes = applicant_attributes
      .reject { |key| !key.is_a?(Symbol) || key == :snap_application_date }
      .index_with(nil)
    update!(clear_attributes)
  end

  def is_applicant_attribute_required?(attribute)
    get_required_applicant_attributes
    .include?(attribute)
  end

  private

  def parse_date(value)
    return value if value.is_a?(Date)

    if value.is_a?(String) && value.present?
      begin
        Date.strptime(value, "%m/%d/%Y")
      rescue ArgumentError
        nil
      end
    end
  end

  def redactable_fields_from_config
    return {} unless agency_config

    agency_config.applicant_attributes
      .select { |_name, attr| attr.redactable }
      .each_with_object({}) { |(name, attr), h| h[name.to_sym] = attr.redact_type.to_sym }
  end

  def redact_member_names_in_json(json_array)
    return json_array unless json_array.is_a?(Array)

    json_array.map do |income_change|
      next income_change unless income_change.is_a?(Hash)

      income_change.with_indifferent_access.tap do |record|
        record["member_name"] = Redactable::REDACTION_REPLACEMENTS[:string] if record.key?("member_name")
      end
    end
  end

  def get_required_applicant_attributes
    agency_config&.applicant_attributes&.select { |key, attributes| attributes["required"] }&.keys&.map(&:to_sym) || []
  end

  def agency_config
    ClientAgencyConfig.instance[client_agency_id]
  end
end
