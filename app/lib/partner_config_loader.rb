require "yaml"
require "net/http"
require "uri"

# Loads a partner configuration from TWO documents and upserts it into the
# database:
#
#   * settings    — shared, environment-agnostic config that is IDENTICAL across
#                   environments (identity, feature flags, application
#                   attributes, translations). Safe to reuse verbatim in demo and
#                   prod.
#   * credentials — the per-environment values that MUST differ between
#                   environments and must never be promoted (argyle mode,
#                   weekly report recipients, and the whole transmission_methods
#                   block including secrets).
#
# The two documents are fetched independently (each may be a local file path or
# an https:// URL — mix and match is fine) and shallow-merged before validate/
# apply
class PartnerConfigLoader
  class ValidationError < StandardError; end
  class SourceError < StandardError; end

  # Column attrs that belong in the SETTINGS document (shared across envs).
  SETTINGS_ATTRS = %w[
    partner_id name state_name timezone domain website logo_path
    active_demo active_prod pilot_ended
    staff_portal_enabled generic_links_enabled invitation_links_enabled
    invitation_valid_days_default
    pay_income_days_w2 pay_income_days_gig
    report_customization_show_earnings_list
    include_paystubs
    include_full_ssn include_direct_deposit_last_4
    weekly_report_enabled weekly_report_variant
    include_invitation_details_on_weekly_report
    partner_identifier_name
    default_origin
  ].freeze

  # Column attrs that belong in the CREDENTIALS document (per-environment).
  # `partner_id` is duplicated here purely as a pairing cross-check.
  CREDENTIAL_ATTRS = %w[
    partner_id
    argyle_environment weekly_report_recipients
  ].freeze

  # Structural (non-column) top-level keys, partitioned the same way.
  SETTINGS_STRUCTURAL = %w[application_attributes translations].freeze
  CREDENTIAL_STRUCTURAL = %w[transmission_methods].freeze

  SETTINGS_TOP_LEVEL = (SETTINGS_ATTRS + SETTINGS_STRUCTURAL).freeze
  CREDENTIAL_TOP_LEVEL = (CREDENTIAL_ATTRS + CREDENTIAL_STRUCTURAL).freeze

  # DB columns to assign on the model — the union of both partitions.
  PARTNER_CONFIG_ATTRS = (SETTINGS_ATTRS | CREDENTIAL_ATTRS).freeze

  REQUIRED_ATTRS = %w[partner_id name timezone pay_income_days_w2 pay_income_days_gig partner_identifier_name].freeze

  # Credential attrs that must be present (with a valid value) in every env.
  REQUIRED_CREDENTIAL_ATTRS = %w[argyle_environment].freeze
  VALID_ARGYLE_ENVIRONMENTS = %w[sandbox production].freeze

  # Config keys each transmission method must supply, per method_type. Enforced
  # so a credentials file that omits (or leaves blank) a value fails loudly at
  # apply instead of producing a silently-broken transmitter. Keys listed in
  # BLANK_ALLOWED_KEYS must be present but may be blank (e.g. path_prefix = root).
  # Derived from the transmitter services (SftpGateway, WebhookTransmitter, etc.).
  REQUIRED_CREDENTIAL_KEYS = {
    "sftp" => %w[url user password path_prefix],
    "webhook" => %w[webhook_url api_key],
    "json" => %w[url],
    "shared_email" => %w[email],
    "encrypted_s3" => %w[public_key path_prefix],
    "unencrypted_s3" => %w[path_prefix]
  }.freeze
  BLANK_ALLOWED_KEYS = %w[path_prefix].freeze

  # Sentinel written by .export in place of an encrypted secret value. It is a
  # human-readable placeholder, NOT a real value — applying it verbatim is a
  # mistake, so #validate_no_masked_placeholders rejects it.
  MASKED_PLACEHOLDER = "$ENCRYPTED".freeze

  # Structural key-name allowlists for nested sections (typo/stale-format guard).
  TRANSMISSION_METHOD_KEYS = %w[method_type configs].freeze
  TRANSMISSION_CONFIG_KEYS = %w[key value encrypted].freeze
  APPLICATION_ATTRIBUTE_KEYS = %w[
    name description required data_type form_field_type
    show_on_applicant_form show_on_caseworker_form show_on_caseworker_report
    redactable redact_type
  ].freeze

  # Subdomain prefixes reserved for non-partner infrastructure. A partner
  # claiming one of these would never receive traffic — DNS for the
  # subdomain points elsewhere (e.g. `static` is the CloudFront-fronted
  # static-assets CDN).
  RESERVED_DOMAIN_PREFIXES = %w[static].freeze

  VALID_TRANSMISSION_METHODS = PartnerTransmissionMethod.method_types.keys.freeze
  VALID_DATA_TYPES = PartnerApplicationAttribute.data_types.keys.freeze
  VALID_PAY_INCOME_DAYS = [ 90, 182 ].freeze

  REQUIRED_TRANSLATION_KEYS = %w[
    shared.agency_full_name
    shared.header.cbv_flow_title
    shared.header.preheader
  ].freeze

  attr_reader :yaml_data, :settings_data, :credentials_data, :errors, :warnings

  def initialize(settings_source, credentials_source)
    @settings_source = settings_source
    @credentials_source = credentials_source
    @errors = []
    @warnings = []
    @yaml_data = nil
    @settings_data = nil
    @credentials_data = nil
  end

  # ---------------------------------------------------------------------------
  # Loading
  # ---------------------------------------------------------------------------

  def load!
    @settings_data = parse(fetch_source(@settings_source))
    @credentials_data = parse(fetch_source(@credentials_source))
    # Shallow merge: the partition is clean (no shared key but partner_id, which
    # is identical), so credentials simply overlay settings.
    @yaml_data = @settings_data.merge(@credentials_data)
    self
  rescue Psych::SyntaxError => e
    raise SourceError, "Invalid YAML: #{e.message}"
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  def validate!
    raise "Call load! first" unless @yaml_data
    @errors = []
    @warnings = []

    validate_partition
    validate_partner_id_match
    validate_no_unknown_nested_keys
    validate_required_attrs
    validate_required_credential_attrs
    validate_transmission_methods
    validate_required_credential_keys
    validate_no_masked_placeholders
    validate_pay_income_days
    validate_domain
    validate_application_attributes
    validate_partner_identifier_name
    validate_translations

    self
  end

  def valid?
    @errors.empty?
  end

  # ---------------------------------------------------------------------------
  # Apply (upsert DB to match the merged config)
  # ---------------------------------------------------------------------------

  def apply!
    raise "Call load! and validate! first" unless @yaml_data
    raise ValidationError, "Cannot apply invalid config:\n  #{@errors.join("\n  ")}" unless valid?

    partner_id = @yaml_data[:partner_id]
    changes = { config: nil, transmission_methods: { created: 0, updated: 0, deleted: 0 },
                application_attributes: { created: 0, updated: 0, deleted: 0 },
                translations: { created: 0, updated: 0, deleted: 0 } }

    ActiveRecord::Base.transaction do
      pc = PartnerConfig.find_or_initialize_by(partner_id: partner_id)
      is_new = pc.new_record?

      config_attrs = @yaml_data.slice(*PARTNER_CONFIG_ATTRS)
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
  # Export (DB -> { settings:, credentials: } hashes)
  # ---------------------------------------------------------------------------
  #
  # Returns two string-keyed hashes ready to be written as the shared settings
  # document and the (env-specific) credentials document. Encrypted transmission
  # values are masked with MASKED_PLACEHOLDER so an export never leaks secrets;
  # the resulting credentials document is therefore a snapshot/skeleton, not a
  # re-appliable file (masked values must be replaced with the real secret).
  def self.export(partner_id)
    pc = PartnerConfig.find_by!(partner_id: partner_id)

    settings = {}
    SETTINGS_ATTRS.each { |attr| settings[attr] = pc.send(attr) }

    settings["application_attributes"] = pc.partner_application_attributes.map do |attr|
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

    settings["translations"] = {}
    pc.partner_translations.order(:locale, :key).each do |t|
      settings["translations"][t.locale] ||= {}
      settings["translations"][t.locale][t.key] = t.value
    end
    settings["translations"] = nil if settings["translations"].empty?

    credentials = {}
    CREDENTIAL_ATTRS.each { |attr| credentials[attr] = pc.send(attr) }

    credentials["transmission_methods"] = pc.partner_transmission_methods.map do |ptm|
      method_data = { "method_type" => ptm.method_type }
      method_data["configs"] = ptm.partner_transmission_configs.map do |tc|
        entry = { "key" => tc.key, "encrypted" => tc.is_encrypted }
        entry["value"] = tc.is_encrypted ? MASKED_PLACEHOLDER : tc[:value]
        entry
      end
      method_data
    end

    { settings: settings.compact, credentials: credentials.compact }
  end

  private

  def parse(raw)
    YAML.safe_load(raw, permitted_classes: [ Symbol ]).to_h.with_indifferent_access
  end

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
  # Validation helpers
  # ---------------------------------------------------------------------------

  # Enforce the settings/credentials partition at the top level: a key found in
  # the wrong document fails loudly (so a credential can't hide in the settings
  # document, or a shared setting drift into a per-env file), and an entirely
  # unknown key is rejected as a typo/stale format.
  def validate_partition
    (@settings_data.keys.map(&:to_s) - SETTINGS_TOP_LEVEL).sort.each do |key|
      @errors << if CREDENTIAL_TOP_LEVEL.include?(key)
                   "Settings file contains credential key '#{key}' (belongs in the credentials file)"
                 else
                   "Settings file: unknown top-level key '#{key}'"
                 end
    end

    (@credentials_data.keys.map(&:to_s) - CREDENTIAL_TOP_LEVEL).sort.each do |key|
      @errors << if SETTINGS_TOP_LEVEL.include?(key)
                   "Credentials file contains settings key '#{key}' (belongs in the settings file)"
                 else
                   "Credentials file: unknown top-level key '#{key}'"
                 end
    end
  end

  def validate_partner_id_match
    settings_id = @settings_data[:partner_id]
    credentials_id = @credentials_data[:partner_id]
    @errors << "Missing partner_id in settings file" if settings_id.blank?
    @errors << "Missing partner_id in credentials file" if credentials_id.blank?
    if settings_id.present? && credentials_id.present? && settings_id.to_s != credentials_id.to_s
      @errors << "partner_id mismatch: settings='#{settings_id}' vs credentials='#{credentials_id}'"
    end
  end

  # Reject unknown keys inside the structured `transmission_methods[].configs[]`
  # and `application_attributes[]` sections so a typo fails loudly instead of
  # being silently dropped on apply. Translation keys are data, not schema, so
  # they are intentionally not checked here.
  def validate_no_unknown_nested_keys
    Array(@yaml_data[:transmission_methods]).each_with_index do |tm, i|
      next unless tm.respond_to?(:keys)
      (tm.keys.map(&:to_s) - TRANSMISSION_METHOD_KEYS).sort.each do |key|
        @errors << "transmission_methods[#{i}]: unknown key '#{key}'"
      end
      Array(tm[:configs]).each_with_index do |tc, j|
        next unless tc.respond_to?(:keys)
        (tc.keys.map(&:to_s) - TRANSMISSION_CONFIG_KEYS).sort.each do |key|
          @errors << "transmission_methods[#{i}].configs[#{j}]: unknown key '#{key}'"
        end
      end
    end

    Array(@yaml_data[:application_attributes]).each_with_index do |attr, i|
      next unless attr.respond_to?(:keys)
      (attr.keys.map(&:to_s) - APPLICATION_ATTRIBUTE_KEYS).sort.each do |key|
        @errors << "application_attributes[#{i}]: unknown key '#{key}'"
      end
    end
  end

  def validate_required_attrs
    REQUIRED_ATTRS.each do |attr|
      @errors << "Missing required attribute: #{attr}" if @yaml_data[attr].blank?
    end
  end

  def validate_required_credential_attrs
    env = @credentials_data[:argyle_environment]
    if env.blank?
      @errors << "Missing required credential: argyle_environment"
    elsif !VALID_ARGYLE_ENVIRONMENTS.include?(env.to_s)
      @errors << "Invalid argyle_environment '#{env}'. Valid: #{VALID_ARGYLE_ENVIRONMENTS.join(', ')}"
    end
  end

  def validate_transmission_methods
    if @yaml_data.key?(:transmission_method)
      @errors << "Use 'transmission_methods' (plural), not 'transmission_method'"
      return
    end

    methods = @yaml_data[:transmission_methods]
    if methods.blank?
      @errors << "At least one transmission method is required"
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
      end
    end
  end

  # Every transmission method must supply the config keys its transmitter needs
  # (see REQUIRED_CREDENTIAL_KEYS) — present, and non-blank unless the key is
  # explicitly blank-allowed. This is the "throw errors if missing" guarantee at
  # the individual-credential level.
  def validate_required_credential_keys
    Array(@yaml_data[:transmission_methods]).each_with_index do |tm, i|
      method_type = tm[:method_type].to_s
      required = REQUIRED_CREDENTIAL_KEYS[method_type]
      next if required.nil?

      values = Array(tm[:configs]).each_with_object({}) { |tc, h| h[tc[:key].to_s] = tc[:value] }
      required.each do |key|
        if !values.key?(key)
          @errors << "transmission_methods[#{i}] (#{method_type}): missing required credential '#{key}'"
        elsif BLANK_ALLOWED_KEYS.exclude?(key) && values[key].to_s.strip.empty?
          @errors << "transmission_methods[#{i}] (#{method_type}): credential '#{key}' must not be blank"
        end
      end
    end
  end

  # An exported credentials document masks encrypted secrets as MASKED_PLACEHOLDER.
  # Applying that verbatim would store the literal sentinel as the secret, so
  # reject it — the operator must substitute the real value first.
  def validate_no_masked_placeholders
    Array(@yaml_data[:transmission_methods]).each_with_index do |tm, i|
      Array(tm[:configs]).each_with_index do |tc, j|
        next unless tc[:value].to_s == MASKED_PLACEHOLDER
        @errors << "transmission_methods[#{i}].configs[#{j}] (#{tc[:key]}): value is the masked placeholder #{MASKED_PLACEHOLDER}; replace it with the real secret before applying"
      end
    end
  end

  def validate_pay_income_days
    %w[pay_income_days_w2 pay_income_days_gig].each do |attr|
      val = @yaml_data[attr]
      next if val.blank? # already caught by required check
      unless VALID_PAY_INCOME_DAYS.include?(val.to_i)
        @errors << "Invalid #{attr} '#{val}'. Valid: #{VALID_PAY_INCOME_DAYS.join(', ')}"
      end
    end
  end

  def validate_domain
    domain = @yaml_data[:domain]
    return if domain.blank?
    if RESERVED_DOMAIN_PREFIXES.include?(domain.to_s.downcase)
      @errors << "Invalid domain '#{domain}'. Reserved prefixes: #{RESERVED_DOMAIN_PREFIXES.join(', ')}"
    end
  end

  def validate_application_attributes
    attrs = @yaml_data[:application_attributes] || []
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

  def validate_partner_identifier_name
    name = @yaml_data[:partner_identifier_name]
    return if name.blank?
    attrs = @yaml_data[:application_attributes] || []
    matching = attrs.find { |a| a[:name].to_s == name.to_s }
    if matching.nil?
      @errors << "partner_identifier_name '#{name}' must be defined as an entry in application_attributes"
    elsif !matching[:required]
      @errors << "partner_identifier_name '#{name}' must reference an application_attribute with required: true"
    end
  end

  def validate_translations
    translations = @yaml_data[:translations] || {}
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
    yaml_methods = @yaml_data[:transmission_methods] || []
    yaml_method_types = yaml_methods.map { |m| m[:method_type].to_s }

    # Delete transmission methods not in the merged config
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
        value = tc_data[:value]
        existing = ptm.partner_transmission_configs.find_by(key: tc_data[:key])
        if existing
          existing.update!(is_encrypted: tc_data.fetch(:encrypted, false), value: value)
          counts[:updated] += 1
        else
          ptm.partner_transmission_configs.create!(
            key: tc_data[:key],
            is_encrypted: tc_data.fetch(:encrypted, false),
            value: value
          )
          counts[:created] += 1
        end
      end
    end

    counts
  end

  def reconcile_application_attributes(pc)
    counts = { created: 0, updated: 0, deleted: 0 }
    yaml_attrs = @yaml_data[:application_attributes] || []
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
    translations = @yaml_data[:translations] || {}

    # Build set of (locale, key) pairs from the merged config
    yaml_pairs = Set.new
    translations.each do |locale, entries|
      (entries || {}).each_key { |translation_key| yaml_pairs.add([ locale.to_s, translation_key.to_s ]) }
    end

    # Delete translations not in the merged config
    pc.partner_translations.each do |t|
      unless yaml_pairs.include?([ t.locale, t.key ])
        t.destroy!
        counts[:deleted] += 1
      end
    end

    # Upsert translations from the merged config
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
