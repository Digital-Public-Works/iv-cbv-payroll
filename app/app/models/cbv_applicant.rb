class CbvApplicant < ApplicationRecord
  include Redactable

  after_initialize :set_snap_application_date, if: :new_record?
  after_initialize :set_applicant_attributes
  attr_reader :applicant_attributes, :required_applicant_attributes

  def self.valid_attributes_for_agency(client_agency_id)
    agency = ClientAgencyConfig.instance[client_agency_id]
    agency.applicant_attributes.keys.map(&:to_sym)
  end

  def self.build_custom_attributes(client_agency_id, &value_provider)
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

    apply_redaction!(fields_to_redact || {})

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

  # retrurns the names of any attributes that are nil. false, [], {} are valid values for an attribute
  def missing_required_attributes
    @required_applicant_attributes.select do |attr|
      self.send(attr).nil?
    end
  end

  def validate_base_and_applicant_attributes?
    valid? && validate_required_applicant_attributes.empty?
  end

  def validate_required_applicant_attributes
    missing_attrs = missing_required_attributes

    missing_attrs.each do |attr|
      errors.add(attr, I18n.t("cbv.applicant_informations.#{client_agency_id}.fields.#{attr}.blank",
        default: I18n.t("cbv.applicant_informations.default.fields.#{attr}.blank", default: "is required")))
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

  # reset applicant custom attribute to nil
  def reset_applicant_attributes
    real_columns = self.class.column_names
    applicant_attributes
      .each do |key|
        next unless key.is_a?(Symbol)
        next if key == :snap_application_date

        if real_columns.include?(key.to_s)
          self[key] = nil
        else
          write_applicant_attribute(key, nil)
        end
      end
    save!
  end

  def is_applicant_attribute_required?(attribute)
    get_required_applicant_attributes
    .include?(attribute)
  end

  # logic to ensure that the jsonb column partner custom attributes can be accessed via reflection
  def method_missing(method_name, *args, &block)
    name = method_name.to_s
    is_setter = name.end_with?("=")
    attr_name = is_setter ? name.chomp("=") : name

    if is_setter && writable_applicant_attribute?(attr_name)
      write_applicant_attribute(attr_name, args.first)
    elsif !is_setter && readable_applicant_attribute?(attr_name)
      read_applicant_attribute(attr_name)
    else
      super
    end
  end

  # dynamic property reading and writing for the jsonb attributes that are not actual entity columns in the db
  def respond_to_missing?(method_name, include_private = false)
    name = method_name.to_s
    if name.end_with?("=")
      writable_applicant_attribute?(name.chomp("=")) || super
    else
      readable_applicant_attribute?(name) || super
    end
  end

  private

  # verify that the attribute name being used here is actually defined as part of the partners custom attributes
  def writable_applicant_attribute?(name)
    dynamic_applicant_attribute?(name)
  end

  def readable_applicant_attribute?(name)
    dynamic_applicant_attribute?(name)
  end

  def dynamic_applicant_attribute?(name)
    return false if name.blank?
    return false if self.class.column_names.include?(name)
    cfg = agency_config
    return false unless cfg
    attrs = cfg.applicant_attributes
    attrs.key?(name) || attrs.key?(name.to_sym)
  end

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

  def partner_identifier_redactable?
    return false unless agency_config && agency_config.partner_identifier_name
    attr = agency_config.applicant_attributes[agency_config.partner_identifier_name]
    !!(attr && attr.redactable)
  end

  # Apply redaction to whatever backs each field — real columns get assigned
  # directly; partner-defined attributes get routed through write_applicant_attribute
  # so the jsonb / partner_identifier column is updated correctly.
  def apply_redaction!(fields_to_redact)
    real_columns = self.class.column_names
    fields_to_redact.each do |field, type|
      replacement = Redactable::REDACTION_REPLACEMENTS[type]
      if real_columns.include?(field.to_s)
        self[field] = replacement
      else
        write_applicant_attribute(field, replacement)
      end
    end
  end

  # Read a partner-defined applicant attribute. The value lives either in the
  # `partner_identifier` column (if `name` matches the agency's
  # `partner_identifier_name`) or in the `custom_attributes` jsonb.
  # Real ActiveRecord columns (e.g. `snap_application_date`) take precedence
  # via the `super` chain in method_missing.
  def read_applicant_attribute(name)
    name = name.to_s
    return partner_identifier if name == agency_config&.partner_identifier_name.to_s
    (custom_attributes || {})[name]
  end

  def write_applicant_attribute(name, value)
    name = name.to_s
    if name == agency_config&.partner_identifier_name.to_s
      self.partner_identifier = value
    else
      self.custom_attributes = (custom_attributes || {}).merge(name => value)
    end
    value
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
