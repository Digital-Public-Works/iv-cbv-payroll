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
    active_demo active_prod
    staff_portal_enabled generic_links_enabled invitation_links_enabled
    invitation_valid_days_default
    pay_income_days_w2 pay_income_days_gig
    report_customization_show_earnings_list
    include_paystubs
    include_full_ssn include_direct_deposit_last_4
    encourage_link_sharing
    allow_user_comment allow_outside_jobs
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
  # Per-context lists of which application_attributes the partner asks for, and
  # whether each is required there. Each entry is { name:, required: }.
  ATTRIBUTE_USAGE_SECTIONS = {
    "invitation_attributes" => PartnerAttributeUsage::INVITATION,
    "landing_page_attributes" => PartnerAttributeUsage::LANDING_PAGE,
    "applicant_input_page" => PartnerAttributeUsage::APPLICANT_INPUT_PAGE
  }.freeze
  ATTRIBUTE_USAGE_KEYS = %w[name required].freeze

  SETTINGS_STRUCTURAL = (%w[application_attributes translations] + ATTRIBUTE_USAGE_SECTIONS.keys).freeze
  CREDENTIAL_STRUCTURAL = %w[transmission_methods].freeze

  SETTINGS_TOP_LEVEL = (SETTINGS_ATTRS + SETTINGS_STRUCTURAL).freeze
  CREDENTIAL_TOP_LEVEL = (CREDENTIAL_ATTRS + CREDENTIAL_STRUCTURAL).freeze

  # DB columns to assign on the model — the union of both partitions.
  PARTNER_CONFIG_ATTRS = (SETTINGS_ATTRS | CREDENTIAL_ATTRS).freeze

  # Sections apply_scoped! can reconcile.
  SETTINGS_SECTIONS = %i[application_attributes attribute_usages translations].freeze
  ALL_SECTIONS = (SETTINGS_SECTIONS + %i[transmission_methods]).freeze

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

  # Optional config keys each transmitter reads, and the keys that hold secrets
  # (stored encrypted by default). Not enforced by validation; declared here,
  # next to REQUIRED_CREDENTIAL_KEYS, so the admin API's schema endpoint can
  # describe every method's form. Transmission config keys can't be
  # introspected from the database (a generic key/value bag).
  OPTIONAL_CREDENTIAL_KEYS = {
    "sftp" => %w[port],
    "webhook" => %w[],
    "json" => %w[include_report_pdf custom_headers api_key],
    "shared_email" => %w[],
    "encrypted_s3" => %w[bucket region aws_access_key_id aws_secret_access_key endpoint force_path_style],
    "unencrypted_s3" => %w[bucket region aws_access_key_id aws_secret_access_key endpoint force_path_style]
  }.freeze
  SECRET_CREDENTIAL_KEYS = %w[password api_key aws_secret_access_key].freeze

  # Methods whose path_prefix is used as a remote directory; a leading "/" breaks
  # remote_directory_for at transmission time, so it's rejected up front.
  PATH_PREFIX_METHODS = %w[sftp unencrypted_s3 encrypted_s3].freeze

  # Sentinel written by .export in place of an encrypted secret value. It is a
  # human-readable placeholder, NOT a real value — applying it verbatim is a
  # mistake, so #validate_no_masked_placeholders rejects it.
  MASKED_PLACEHOLDER = "$ENCRYPTED".freeze

  # Structural key-name allowlists for nested sections (typo/stale-format guard).
  TRANSMISSION_METHOD_KEYS = %w[method_type configs].freeze
  TRANSMISSION_CONFIG_KEYS = %w[key value encrypted].freeze
  APPLICATION_ATTRIBUTE_KEYS = %w[
    name description data_type form_field_type
    show_on_caseworker_form show_on_caseworker_report
    redactable redact_type
    validation_regex required_for_submit
  ].freeze

  # Subdomain prefixes reserved for non-partner infrastructure. A partner
  # claiming one of these would never receive traffic — DNS for the
  # subdomain points elsewhere (e.g. `static` is the CloudFront-fronted
  # static-assets CDN).
  # `admin` is the vmi-admin portal's host (admin.<domain>), routed to the
  # portal by the load balancer before VMI sees it.
  RESERVED_DOMAIN_PREFIXES = %w[static admin].freeze

  # partner_ids that would collide with infrastructure hosts.
  RESERVED_PARTNER_IDS = %w[admin].freeze

  VALID_TRANSMISSION_METHODS = PartnerTransmissionMethod.method_types.keys.freeze
  VALID_DATA_TYPES = PartnerApplicationAttribute.data_types.keys.freeze
  VALID_PAY_INCOME_DAYS = [ 90, 182 ].freeze

  REQUIRED_TRANSLATION_KEYS = %w[
    shared.agency_full_name
    shared.header.cbv_flow_title
    shared.header.preheader
  ].freeze

  attr_reader :yaml_data, :settings_data, :credentials_data, :errors, :warnings

  # Errors and warnings as { message:, path: } hashes, where path points at the
  # offending field (e.g. "application_attributes[2].validation_regex"). The
  # admin API returns these; #errors / #warnings keep the plain messages.
  attr_reader :error_details, :warning_details

  # [method_type, key] pairs whose submitted value is MASKED_PLACEHOLDER and
  # which are stored encrypted: "keep the stored secret" (see #keep_stored_secrets!).
  attr_reader :kept_secrets

  def initialize(settings_source, credentials_source)
    @settings_source = settings_source
    @credentials_source = credentials_source
    @errors = []
    @warnings = []
    @error_details = []
    @warning_details = []
    @kept_secrets = Set.new
    @yaml_data = nil
    @settings_data = nil
    @credentials_data = nil
  end

  # A loader over documents that are already parsed (the admin API's JSON
  # bodies, or a document built from the database), instead of sources to fetch.
  def self.from_documents(settings, credentials)
    new(nil, nil).load_documents!(settings, credentials)
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

  def load_documents!(settings, credentials)
    @settings_data = settings.to_h.with_indifferent_access
    @credentials_data = credentials.to_h.with_indifferent_access
    @yaml_data = @settings_data.merge(@credentials_data)
    self
  end

  # keep what is present for secrets if the configured masked placholder is submitted, do not overwrite.
  # overwrite if something else is submitted
  def keep_stored_secrets!(partner_config)
    raise "Call load! first" unless @yaml_data
    @kept_secrets = Set.new
    return self if partner_config.nil?

    Array(@yaml_data[:transmission_methods]).each do |tm|
      next unless tm.respond_to?(:keys)
      Array(tm[:configs]).each do |tc|
        next unless tc.respond_to?(:keys) && tc[:value].to_s == MASKED_PLACEHOLDER
        next if tc.key?(:encrypted) && tc[:encrypted] == false

        stored = partner_config.partner_transmission_methods.find { |m| m.method_type == tm[:method_type].to_s }
        config = stored&.partner_transmission_configs&.find { |c| c.key == tc[:key].to_s }
        @kept_secrets << [ tm[:method_type].to_s, tc[:key].to_s ] if config&.is_encrypted
      end
    end
    self
  end

  def kept_secret?(method_type, key)
    @kept_secrets.include?([ method_type.to_s, key.to_s ])
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  def validate!
    raise "Call load! first" unless @yaml_data
    @errors = []
    @warnings = []
    @error_details = []
    @warning_details = []

    # Later checks index into these sections; stop before they'd raise on a
    # wrongly shaped document (e.g. a list where a mapping belongs).
    validate_shapes
    return self unless valid?

    validate_partition
    validate_partner_id_match
    validate_no_unknown_nested_keys
    validate_required_attrs
    validate_required_credential_attrs
    validate_transmission_methods
    validate_required_credential_keys
    validate_webhook_contract_version
    validate_no_masked_placeholders
    validate_pay_income_days
    validate_domain
    validate_reserved_partner_id
    validate_path_prefixes
    validate_application_attributes
    validate_attribute_usages
    validate_validation_regexes
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

  # Upserts the whole partner: every column, then a destructive reconcile of
  # every section (anything not in the documents is deleted). Used by the rake
  # task and by admin-API imports of both documents.
  def apply!
    apply_scoped!(scalar_keys: PARTNER_CONFIG_ATTRS, sections: ALL_SECTIONS)
  end

  # Settings only: settings columns and sections. Credentials (argyle mode,
  # report recipients, transmission methods and their ciphertext) are left as
  # they are. Used by promotion and by settings-only imports; validate against
  # the target's current credentials first.
  def apply_settings!
    apply_scoped!(scalar_keys: SETTINGS_ATTRS, sections: SETTINGS_SECTIONS)
  end

  # Applies only the named columns and sections. Anything not named is left
  # untouched, including columns this loader doesn't know about. The admin
  # API's partial updates use this; the documents must still be complete
  # enough to validate.
  def apply_scoped!(scalar_keys:, sections:)
    raise "Call load! and validate! first" unless @yaml_data
    raise ValidationError, "Cannot apply invalid config:\n  #{@errors.join("\n  ")}" unless valid?
    unknown = sections.map(&:to_sym) - ALL_SECTIONS
    raise ArgumentError, "Unknown sections: #{unknown.join(', ')}" if unknown.any?

    partner_id = @yaml_data[:partner_id]
    empty = { created: 0, updated: 0, deleted: 0 }
    changes = { config: nil, transmission_methods: empty.dup, application_attributes: empty.dup,
                attribute_usages: empty.dup, translations: empty.dup }

    ActiveRecord::Base.transaction do
      pc = PartnerConfig.find_or_initialize_by(partner_id: partner_id)
      is_new = pc.new_record?

      config_attrs = @yaml_data.slice(*(PARTNER_CONFIG_ATTRS & scalar_keys.map(&:to_s)))
      pc.assign_attributes(config_attrs)
      changes[:config] = is_new ? :created : (pc.changed? ? :updated : :unchanged)
      pc.save!

      changes[:transmission_methods] = reconcile_transmission_methods(pc) if sections.include?(:transmission_methods)
      changes[:application_attributes] = reconcile_application_attributes(pc) if sections.include?(:application_attributes)
      changes[:attribute_usages] = reconcile_attribute_usages(pc) if sections.include?(:attribute_usages)
      changes[:translations] = reconcile_translations(pc) if sections.include?(:translations)

      # partner_configs.updated_at is the partner's version token (the admin
      # API's concurrency check), so a change to any section moves it.
      section_changed = changes.except(:config).values.any? { |c| c.values.sum.positive? }
      pc.touch if changes[:config] == :unchanged && section_changed
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
  #
  # include_secrets: true decrypts them instead, for backups that must re-apply
  # as-is (the admin API's "export with secrets"). The rake task never asks for it.
  def self.export(partner_id, include_secrets: false)
    # Rows are ordered by id so the same config always exports identically.
    pc = PartnerConfig.find_by!(partner_id: partner_id)

    settings = {}
    SETTINGS_ATTRS.each { |attr| settings[attr] = pc.send(attr) }

    settings["application_attributes"] = pc.partner_application_attributes.order(:id).map do |attr|
      {
        "name" => attr.name,
        "description" => attr.description,
        "data_type" => attr.data_type,
        "form_field_type" => attr.form_field_type,
        "show_on_caseworker_form" => attr.show_on_caseworker_form,
        "show_on_caseworker_report" => attr.show_on_caseworker_report,
        "redactable" => attr.redactable,
        "redact_type" => attr.redact_type,
        "validation_regex" => attr.validation_regex,
        "required_for_submit" => attr.required_for_submit
      }.compact
    end

    ATTRIBUTE_USAGE_SECTIONS.each do |section, context|
      settings[section] = pc.partner_attribute_usages.for_context(context).ordered.map do |usage|
        { "name" => usage.name, "required" => usage.required }
      end
    end

    settings["translations"] = {}
    pc.partner_translations.order(:locale, :key).each do |t|
      settings["translations"][t.locale] ||= {}
      settings["translations"][t.locale][t.key] = t.value
    end
    settings["translations"] = nil if settings["translations"].empty?

    credentials = {}
    CREDENTIAL_ATTRS.each { |attr| credentials[attr] = pc.send(attr) }

    credentials["transmission_methods"] = pc.partner_transmission_methods.order(:id).map do |ptm|
      method_data = { "method_type" => ptm.method_type }
      method_data["configs"] = ptm.partner_transmission_configs.order(:id).map do |tc|
        entry = { "key" => tc.key, "encrypted" => tc.is_encrypted }
        entry["value"] = if !tc.is_encrypted then tc[:value]
                         elsif include_secrets then tc.value
                         else MASKED_PLACEHOLDER
                         end
        entry
      end
      method_data
    end

    { settings: settings.compact, credentials: credentials.compact }
  end

  private

  def add_error(message, path = nil)
    @errors << message
    @error_details << { message: message, path: path }.compact
  end

  def add_warning(message, path = nil)
    @warnings << message
    @warning_details << { message: message, path: path }.compact
  end

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

  def validate_shapes
    {
      "application_attributes" => Array, "transmission_methods" => Array, "translations" => Hash
    }.merge(ATTRIBUTE_USAGE_SECTIONS.keys.index_with { Array }).each do |section, type|
      value = @yaml_data[section]
      next if value.nil?
      unless value.is_a?(type)
        add_error("#{section} must be a #{type == Array ? 'list' : 'mapping'}", section)
        next
      end

      entries = type == Array ? value.each_with_index.map { |v, i| [ "#{section}[#{i}]", v ] } : value.map { |k, v| [ "#{section}.#{k}", v ] }
      entries.each do |path, entry|
        add_error("#{path} must be a mapping", path) unless entry.is_a?(Hash) || (type == Hash && entry.nil?)
      end
    end

    Array(@yaml_data[:transmission_methods]).each_with_index do |tm, i|
      next unless tm.is_a?(Hash) && !tm[:configs].nil?
      unless tm[:configs].is_a?(Array) && tm[:configs].all? { |c| c.is_a?(Hash) }
        add_error("transmission_methods[#{i}].configs must be a list of mappings", "transmission_methods[#{i}]")
      end
    end
  end

  # Enforce the settings/credentials partition at the top level: a key found in
  # the wrong document fails loudly (so a credential can't hide in the settings
  # document, or a shared setting drift into a per-env file), and an entirely
  # unknown key is rejected as a typo/stale format.
  def validate_partition
    (@settings_data.keys.map(&:to_s) - SETTINGS_TOP_LEVEL).sort.each do |key|
      add_error(if CREDENTIAL_TOP_LEVEL.include?(key)
                  "Settings file contains credential key '#{key}' (belongs in the credentials file)"
                else
                  "Settings file: unknown top-level key '#{key}'"
                end, key)
    end

    (@credentials_data.keys.map(&:to_s) - CREDENTIAL_TOP_LEVEL).sort.each do |key|
      add_error(if SETTINGS_TOP_LEVEL.include?(key)
                  "Credentials file contains settings key '#{key}' (belongs in the settings file)"
                else
                  "Credentials file: unknown top-level key '#{key}'"
                end, key)
    end
  end

  def validate_partner_id_match
    settings_id = @settings_data[:partner_id]
    credentials_id = @credentials_data[:partner_id]
    add_error("Missing partner_id in settings file", "partner_id") if settings_id.blank?
    add_error("Missing partner_id in credentials file", "partner_id") if credentials_id.blank?
    if settings_id.present? && credentials_id.present? && settings_id.to_s != credentials_id.to_s
      add_error("partner_id mismatch: settings='#{settings_id}' vs credentials='#{credentials_id}'", "partner_id")
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
        add_error("transmission_methods[#{i}]: unknown key '#{key}'", "transmission_methods[#{i}]")
      end
      Array(tm[:configs]).each_with_index do |tc, j|
        next unless tc.respond_to?(:keys)
        (tc.keys.map(&:to_s) - TRANSMISSION_CONFIG_KEYS).sort.each do |key|
          add_error("transmission_methods[#{i}].configs[#{j}]: unknown key '#{key}'", "transmission_methods[#{i}].configs[#{j}]")
        end
      end
    end

    Array(@yaml_data[:application_attributes]).each_with_index do |attr, i|
      next unless attr.respond_to?(:keys)
      (attr.keys.map(&:to_s) - APPLICATION_ATTRIBUTE_KEYS).sort.each do |key|
        add_error("application_attributes[#{i}]: unknown key '#{key}'", "application_attributes[#{i}]")
      end
    end

    ATTRIBUTE_USAGE_SECTIONS.each_key do |section|
      Array(@yaml_data[section.to_sym]).each_with_index do |entry, i|
        next unless entry.respond_to?(:keys)
        (entry.keys.map(&:to_s) - ATTRIBUTE_USAGE_KEYS).sort.each do |key|
          add_error("#{section}[#{i}]: unknown key '#{key}'", "#{section}[#{i}]")
        end
      end
    end
  end

  def validate_required_attrs
    REQUIRED_ATTRS.each do |attr|
      add_error("Missing required attribute: #{attr}", attr) if @yaml_data[attr].blank?
    end
  end

  def validate_required_credential_attrs
    env = @credentials_data[:argyle_environment]
    if env.blank?
      add_error("Missing required credential: argyle_environment", "argyle_environment")
    elsif !VALID_ARGYLE_ENVIRONMENTS.include?(env.to_s)
      add_error("Invalid argyle_environment '#{env}'. Valid: #{VALID_ARGYLE_ENVIRONMENTS.join(', ')}", "argyle_environment")
    end
  end

  def validate_transmission_methods
    if @yaml_data.key?(:transmission_method)
      add_error("Use 'transmission_methods' (plural), not 'transmission_method'", "transmission_method")
      return
    end

    methods = @yaml_data[:transmission_methods]
    if methods.blank?
      add_error("At least one transmission method is required", "transmission_methods")
      return
    end

    methods.each_with_index do |tm, i|
      method_type = tm[:method_type]
      if method_type.blank?
        add_error("transmission_methods[#{i}]: missing 'method_type'", "transmission_methods[#{i}]")
      elsif !VALID_TRANSMISSION_METHODS.include?(method_type.to_s)
        add_error("transmission_methods[#{i}]: invalid method_type '#{method_type}'. Valid: #{VALID_TRANSMISSION_METHODS.join(', ')}", "transmission_methods[#{i}]")
      end

      (tm[:configs] || []).each_with_index do |tc, j|
        add_error("transmission_methods[#{i}].configs[#{j}]: missing 'key'", "transmission_methods[#{i}].configs[#{j}]") if tc[:key].blank?
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
          add_error("transmission_methods[#{i}] (#{method_type}): missing required credential '#{key}'", "transmission_methods[#{i}]")
        elsif BLANK_ALLOWED_KEYS.exclude?(key) && values[key].to_s.strip.empty?
          add_error("transmission_methods[#{i}] (#{method_type}): credential '#{key}' must not be blank", "transmission_methods[#{i}]")
        end
      end
    end
  end

  def validate_webhook_contract_version
    valid_versions = Transmitters::WebhookTransmitter::CONTRACT_VERSIONS
    Array(@yaml_data[:transmission_methods]).each_with_index do |tm, i|
      next unless tm[:method_type].to_s == "webhook"

      Array(tm[:configs]).each do |tc|
        next unless tc[:key].to_s == "contract_version"
        next if valid_versions.include?(tc[:value].to_s)

        @errors << "transmission_methods[#{i}] (webhook): invalid contract_version '#{tc[:value]}' (must be one of #{valid_versions.join(', ')})"
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
        next if kept_secret?(tm[:method_type], tc[:key])
        add_error("transmission_methods[#{i}].configs[#{j}] (#{tc[:key]}): value is the masked placeholder #{MASKED_PLACEHOLDER}; replace it with the real secret before applying", "transmission_methods[#{i}].configs[#{j}]")
      end
    end
  end

  def validate_pay_income_days
    %w[pay_income_days_w2 pay_income_days_gig].each do |attr|
      val = @yaml_data[attr]
      next if val.blank? # already caught by required check
      unless VALID_PAY_INCOME_DAYS.include?(val.to_i)
        add_error("Invalid #{attr} '#{val}'. Valid: #{VALID_PAY_INCOME_DAYS.join(', ')}", attr)
      end
    end
  end

  def validate_domain
    domain = @yaml_data[:domain]
    return if domain.blank?
    if RESERVED_DOMAIN_PREFIXES.include?(domain.to_s.downcase)
      add_error("Invalid domain '#{domain}'. Reserved prefixes: #{RESERVED_DOMAIN_PREFIXES.join(', ')}", "domain")
    end
  end

  def validate_reserved_partner_id
    partner_id = @yaml_data[:partner_id]
    return if partner_id.blank?
    if RESERVED_PARTNER_IDS.include?(partner_id.to_s.downcase)
      add_error("Invalid partner_id '#{partner_id}'. Reserved: #{RESERVED_PARTNER_IDS.join(', ')}", "partner_id")
    end
  end

  def validate_path_prefixes
    Array(@yaml_data[:transmission_methods]).each_with_index do |tm, i|
      next unless PATH_PREFIX_METHODS.include?(tm[:method_type].to_s)
      Array(tm[:configs]).each_with_index do |tc, j|
        next unless tc[:key].to_s == "path_prefix" && tc[:value].to_s.start_with?("/")
        add_error("transmission_methods[#{i}] (#{tm[:method_type]}): path_prefix must not start with '/'", "transmission_methods[#{i}].configs[#{j}]")
      end
    end
  end

  def validate_application_attributes
    attrs = @yaml_data[:application_attributes] || []
    names = []
    attrs.each_with_index do |attr, i|
      add_error("application_attributes[#{i}]: missing 'name'", "application_attributes[#{i}].name") if attr[:name].blank?
      if attr[:data_type].present? && !VALID_DATA_TYPES.include?(attr[:data_type].to_s)
        add_error("application_attributes[#{i}] (#{attr[:name]}): invalid data_type '#{attr[:data_type]}'. Valid: #{VALID_DATA_TYPES.join(', ')}", "application_attributes[#{i}].data_type")
      end
      if names.include?(attr[:name])
        add_error("application_attributes[#{i}]: duplicate name '#{attr[:name]}'", "application_attributes[#{i}].name")
      end
      names << attr[:name]
    end
  end

  # Every entry in invitation_/landing_page_/applicant_input_page must name an
  # attribute the partner actually defines, and must not repeat within its list.
  def validate_attribute_usages
    defined_names = Array(@yaml_data[:application_attributes]).map { |a| a[:name].to_s }

    ATTRIBUTE_USAGE_SECTIONS.each_key do |section|
      seen = []
      Array(@yaml_data[section.to_sym]).each_with_index do |entry, i|
        name = entry[:name].to_s
        if name.blank?
          add_error("#{section}[#{i}]: missing 'name'", "#{section}[#{i}]")
          next
        end
        unless defined_names.include?(name)
          add_error("#{section}[#{i}]: '#{name}' is not defined in application_attributes", "#{section}[#{i}]")
        end
        add_error("#{section}[#{i}]: duplicate name '#{name}'", "#{section}[#{i}]") if seen.include?(name)
        seen << name
      end
    end
  end

  # Applied to a value the applicant types in, so it has to compile.
  def validate_validation_regexes
    Array(@yaml_data[:application_attributes]).each_with_index do |attr, i|
      source = attr[:validation_regex]
      next if source.blank?

      begin
        Regexp.new(source.to_s)
      rescue RegexpError => e
        add_error("application_attributes[#{i}] (#{attr[:name]}): invalid validation_regex: #{e.message}", "application_attributes[#{i}].validation_regex")
      end
    end
  end

  def validate_partner_identifier_name
    name = @yaml_data[:partner_identifier_name]
    return if name.blank?
    attrs = @yaml_data[:application_attributes] || []
    matching = attrs.find { |a| a[:name].to_s == name.to_s }
    if matching.nil?
      add_error("partner_identifier_name '#{name}' must be defined as an entry in application_attributes", "partner_identifier_name")
      return
    end

    # invitations created by partner via API must have the required attributes.
    # invitations auto created by generic does not require these - they will be collected later.
    usage = Array(@yaml_data[:invitation_attributes]).find { |u| u[:name].to_s == name.to_s }
    if usage && !usage[:required]
      add_error("partner_identifier_name '#{name}' must be required in invitation_attributes", "invitation_attributes")
    end
  end

  def validate_translations
    translations = @yaml_data[:translations] || {}
    %w[en es].each do |locale|
      locale_translations = translations[locale] || {}
      REQUIRED_TRANSLATION_KEYS.each do |key|
        unless locale_translations.key?(key)
          add_warning("Missing recommended translation for locale '#{locale}': #{key}", "translations")
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
        next if existing && kept_secret?(method_type, tc_data[:key])

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
        data_type: attr_data.fetch(:data_type, "string"),
        form_field_type: attr_data.fetch(:form_field_type, "text_field"),
        show_on_caseworker_form: attr_data.fetch(:show_on_caseworker_form, true),
        show_on_caseworker_report: attr_data.fetch(:show_on_caseworker_report, false),
        redactable: attr_data.fetch(:redactable, false),
        redact_type: attr_data[:redact_type],
        validation_regex: attr_data[:validation_regex],
        required_for_submit: attr_data.fetch(:required_for_submit, false)
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

  def reconcile_attribute_usages(pc)
    counts = { created: 0, updated: 0, deleted: 0 }

    ATTRIBUTE_USAGE_SECTIONS.each do |section, context|
      entries = Array(@yaml_data[section.to_sym])
      names = entries.map { |e| e[:name].to_s }

      pc.partner_attribute_usages
        .for_context(context)
        .where.not(name: names)
        .destroy_all
        .tap { |d| counts[:deleted] += d.size }

      entries.each_with_index do |entry, position|
        attrs = { required: !!entry[:required], position: position }
        existing = pc.partner_attribute_usages.for_context(context).find_by(name: entry[:name].to_s)

        if existing
          existing.update!(attrs)
          counts[:updated] += 1
        else
          pc.partner_attribute_usages.create!(attrs.merge(context: context, name: entry[:name].to_s))
          counts[:created] += 1
        end
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
