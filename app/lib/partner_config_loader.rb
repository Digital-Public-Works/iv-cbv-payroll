require "yaml"
require "net/http"
require "uri"

class PartnerConfigLoader
  class ValidationError < StandardError; end
  class SourceError < StandardError; end

  # Columns on PartnerConfig that we manage via YAML.
  PARTNER_CONFIG_ATTRS = %w[
    partner_id name state_name timezone domain website logo_path
    argyle_environment default_origin
    active_demo active_prod pilot_ended
    staff_portal_enabled generic_links_enabled invitation_links_enabled
    invitation_valid_days_default
    pay_income_days_w2 pay_income_days_gig
    report_customization_show_earnings_list
    weekly_report_enabled weekly_report_recipients weekly_report_variant
    include_invitation_details_on_weekly_report
  ].freeze

  REQUIRED_ATTRS = %w[partner_id name timezone pay_income_days_w2 pay_income_days_gig].freeze

  VALID_TRANSMISSION_METHODS = PartnerTransmissionMethod.method_types.keys.freeze
  VALID_DATA_TYPES = PartnerApplicationAttribute.data_types.keys.freeze
  VALID_PAY_INCOME_DAYS = [ 90, 182 ].freeze

  REQUIRED_TRANSLATION_KEYS = %w[
    shared.agency_acronym
    shared.agency_full_name
    shared.header.cbv_flow_title
    shared.header.preheader
    shared.benefit
    shared.reporting_purpose
  ].freeze

  attr_reader :data, :errors, :warnings

  def initialize(source)
    @source = source
    @errors = []
    @warnings = []
    @data = nil
  end

  # ---------------------------------------------------------------------------
  # Loading
  # ---------------------------------------------------------------------------

  def load!
    raw = fetch_source(@source)
    @data = YAML.safe_load(raw, permitted_classes: [ Symbol ]).to_h.with_indifferent_access
    self
  rescue Psych::SyntaxError => e
    raise SourceError, "Invalid YAML: #{e.message}"
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  def validate!
    raise "Call load! first" unless @data
    @errors = []
    @warnings = []

    validate_required_attrs
    validate_transmission_methods
    validate_pay_income_days
    validate_application_attributes
    validate_translations

    self
  end

  def valid?
    @errors.empty?
  end

  # ---------------------------------------------------------------------------
  # Apply (upsert DB to match YAML)
  # ---------------------------------------------------------------------------

  def apply!
    raise "Call load! and validate! first" unless @data
    raise ValidationError, "Cannot apply invalid config:\n  #{@errors.join("\n  ")}" unless valid?

    partner_id = @data[:partner_id]
    changes = { config: nil, transmission_methods: { created: 0, updated: 0, deleted: 0 },
                application_attributes: { created: 0, updated: 0, deleted: 0 },
                translations: { created: 0, updated: 0, deleted: 0 } }

    ActiveRecord::Base.transaction do
      pc = PartnerConfig.find_or_initialize_by(partner_id: partner_id)
      is_new = pc.new_record?

      config_attrs = @data.slice(*PARTNER_CONFIG_ATTRS)
      pc.assign_attributes(config_attrs)
      changes[:config] = is_new ? :created : (pc.changed? ? :updated : :unchanged)
      pc.save!

      changes[:transmission_methods] = reconcile_transmission_methods(pc)
      changes[:application_attributes] = reconcile_application_attributes(pc)
      changes[:translations] = reconcile_translations(pc)
    end

    ClientAgencyConfig.reset!
    changes
  end

  # ---------------------------------------------------------------------------
  # Export (DB -> YAML hash)
  # ---------------------------------------------------------------------------

  def self.export(partner_id)
    pc = PartnerConfig.find_by!(partner_id: partner_id)
    data = {}

    PARTNER_CONFIG_ATTRS.each do |attr|
      data[attr] = pc.send(attr)
    end

    data["transmission_methods"] = pc.partner_transmission_methods.map do |ptm|
      method_data = { "method_type" => ptm.method_type }
      method_data["configs"] = ptm.partner_transmission_configs.map do |tc|
        entry = { "key" => tc.key, "encrypted" => tc.is_encrypted }
        entry["value"] = tc.is_encrypted ? "$ENCRYPTED" : tc[:value]
        entry
      end
      method_data
    end

    data["application_attributes"] = pc.partner_application_attributes.map do |attr|
      {
        "name" => attr.name,
        "description" => attr.description,
        "required" => attr.required,
        "data_type" => attr.data_type,
        "form_field_type" => attr.form_field_type,
        "show_on_applicant_form" => attr.show_on_applicant_form,
        "show_on_caseworker_form" => attr.show_on_caseworker_form,
        "show_on_caseworker_report" => attr.show_on_caseworker_report,
        "redactable" => attr.redactable,
        "redact_type" => attr.redact_type
      }.compact
    end

    data["translations"] = {}
    pc.partner_translations.order(:locale, :key).each do |t|
      data["translations"][t.locale] ||= {}
      data["translations"][t.locale][t.key] = t.value
    end
    data["translations"] = nil if data["translations"].empty?

    data.compact
  end

  private

  # ---------------------------------------------------------------------------
  # Source fetching
  # ---------------------------------------------------------------------------

  def fetch_source(source)
    if source.start_with?("https://")
      fetch_url(source)
    else
      raise SourceError, "File not found: #{source}" unless File.exist?(source)
      File.read(source)
    end
  end

  def fetch_url(url)
    uri = URI.parse(url)
    response = Net::HTTP.get_response(uri)
    raise SourceError, "Failed to fetch #{url}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    response.body
  end

  # ---------------------------------------------------------------------------
  # ENV var resolution
  # ---------------------------------------------------------------------------

  def resolve_env_value(value)
    return value unless value.is_a?(String) && value.start_with?("$")
    return value[1..] if value.start_with?("$$") # escape: $$ -> literal $

    env_var = value[1..]
    ENV.fetch(env_var) { raise ValidationError, "Environment variable #{env_var} is not set (referenced as #{value})" }
  end

  def resolve_env_value_safe(value)
    return [ value, nil ] unless value.is_a?(String) && value.start_with?("$")
    return [ value[1..], nil ] if value.start_with?("$$")

    env_var = value[1..]
    if ENV.key?(env_var)
      [ ENV[env_var], nil ]
    else
      [ nil, "Environment variable #{env_var} is not set (referenced as #{value})" ]
    end
  end

  # ---------------------------------------------------------------------------
  # Validation helpers
  # ---------------------------------------------------------------------------

  def validate_required_attrs
    REQUIRED_ATTRS.each do |attr|
      @errors << "Missing required attribute: #{attr}" if @data[attr].blank?
    end
  end

  def validate_transmission_methods
    methods = @data[:transmission_methods]
    if methods.blank?
      @errors << "At least one transmission method is required"
      return
    end

    unless methods.is_a?(Array)
      @errors << "transmission_methods must be an array"
      return
    end

    methods.each_with_index do |tm, i|
      method_type = tm[:method_type]
      if method_type.blank?
        @errors << "transmission_methods[#{i}]: missing 'method_type'"
      elsif !VALID_TRANSMISSION_METHODS.include?(method_type.to_s)
        @errors << "transmission_methods[#{i}]: invalid method_type '#{method_type}'. Valid: #{VALID_TRANSMISSION_METHODS.join(', ')}"
      end

      (tm[:configs] || []).each_with_index do |tc, j|
        @errors << "transmission_methods[#{i}].configs[#{j}]: missing 'key'" if tc[:key].blank?
        if tc[:value].present?
          _, err = resolve_env_value_safe(tc[:value])
          @warnings << "transmission_methods[#{i}].configs[#{j}] (#{tc[:key]}): #{err}" if err
        end
      end
    end
  end

  def validate_pay_income_days
    %w[pay_income_days_w2 pay_income_days_gig].each do |attr|
      val = @data[attr]
      next if val.blank? # already caught by required check
      unless VALID_PAY_INCOME_DAYS.include?(val.to_i)
        @errors << "Invalid #{attr} '#{val}'. Valid: #{VALID_PAY_INCOME_DAYS.join(', ')}"
      end
    end
  end

  def validate_application_attributes
    attrs = @data[:application_attributes] || []
    names = []
    attrs.each_with_index do |attr, i|
      @errors << "application_attributes[#{i}]: missing 'name'" if attr[:name].blank?
      if attr[:data_type].present? && !VALID_DATA_TYPES.include?(attr[:data_type].to_s)
        @errors << "application_attributes[#{i}] (#{attr[:name]}): invalid data_type '#{attr[:data_type]}'. Valid: #{VALID_DATA_TYPES.join(', ')}"
      end
      if names.include?(attr[:name])
        @errors << "application_attributes[#{i}]: duplicate name '#{attr[:name]}'"
      end
      names << attr[:name]
    end
  end

  def validate_translations
    translations = @data[:translations] || {}
    %w[en es].each do |locale|
      locale_translations = translations[locale] || {}
      REQUIRED_TRANSLATION_KEYS.each do |key|
        unless locale_translations.key?(key)
          @warnings << "Missing recommended translation for locale '#{locale}': #{key}"
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Reconciliation helpers (for apply!)
  # ---------------------------------------------------------------------------

  def reconcile_transmission_methods(pc)
    counts = { created: 0, updated: 0, deleted: 0 }
    yaml_methods = @data[:transmission_methods] || []
    yaml_method_types = yaml_methods.map { |m| m[:method_type].to_s }

    # Delete transmission methods not in YAML
    pc.partner_transmission_methods.where.not(method_type: yaml_method_types).destroy_all.tap { |d| counts[:deleted] = d.size }

    yaml_methods.each do |tm_data|
      method_type = tm_data[:method_type].to_s
      ptm = pc.partner_transmission_methods.find_or_create_by!(method_type: method_type)
      counts[:created] += 1 if ptm.previously_new_record?

      # Reconcile configs within this transmission method
      yaml_configs = tm_data[:configs] || []
      yaml_keys = yaml_configs.map { |c| c[:key] }
      ptm.partner_transmission_configs.where.not(key: yaml_keys).destroy_all

      yaml_configs.each do |tc_data|
        resolved_value = resolve_env_value(tc_data[:value])
        existing = ptm.partner_transmission_configs.find_by(key: tc_data[:key])
        if existing
          existing.update!(is_encrypted: tc_data.fetch(:encrypted, false), value: resolved_value)
          counts[:updated] += 1
        else
          ptm.partner_transmission_configs.create!(
            key: tc_data[:key],
            is_encrypted: tc_data.fetch(:encrypted, false),
            value: resolved_value
          )
          counts[:created] += 1
        end
      end
    end

    counts
  end

  def reconcile_application_attributes(pc)
    counts = { created: 0, updated: 0, deleted: 0 }
    yaml_attrs = @data[:application_attributes] || []
    yaml_names = yaml_attrs.map { |a| a[:name] }

    pc.partner_application_attributes.where.not(name: yaml_names).destroy_all.tap { |d| counts[:deleted] = d.size }

    yaml_attrs.each do |attr_data|
      existing = pc.partner_application_attributes.find_by(name: attr_data[:name])
      attrs = {
        description: attr_data[:description],
        required: attr_data.fetch(:required, true),
        data_type: attr_data.fetch(:data_type, "string"),
        form_field_type: attr_data.fetch(:form_field_type, "text_field"),
        show_on_applicant_form: attr_data.fetch(:show_on_applicant_form, true),
        show_on_caseworker_form: attr_data.fetch(:show_on_caseworker_form, true),
        show_on_caseworker_report: attr_data.fetch(:show_on_caseworker_report, false),
        redactable: attr_data.fetch(:redactable, false),
        redact_type: attr_data[:redact_type]
      }

      if existing
        existing.update!(attrs)
        counts[:updated] += 1
      else
        pc.partner_application_attributes.create!(attrs.merge(name: attr_data[:name]))
        counts[:created] += 1
      end
    end

    counts
  end

  def reconcile_translations(pc)
    counts = { created: 0, updated: 0, deleted: 0 }
    translations = @data[:translations] || {}

    # Build set of (locale, key) pairs from YAML
    yaml_pairs = Set.new
    translations.each do |locale, entries|
      (entries || {}).each_key { |translation_key| yaml_pairs.add([ locale.to_s, translation_key.to_s ]) }
    end

    # Delete translations not in YAML
    pc.partner_translations.each do |t|
      unless yaml_pairs.include?([ t.locale, t.key ])
        t.destroy!
        counts[:deleted] += 1
      end
    end

    # Upsert translations from YAML
    translations.each do |locale, entries|
      (entries || {}).each do |translation_key, translation_value|
        existing = pc.partner_translations.find_by(locale: locale.to_s, key: translation_key.to_s)
        if existing
          if existing.value != translation_value.to_s
            existing.update!(value: translation_value.to_s)
            counts[:updated] += 1
          end
        else
          pc.partner_translations.create!(locale: locale.to_s, key: translation_key.to_s, value: translation_value.to_s)
          counts[:created] += 1
        end
      end
    end

    counts
  end
end
