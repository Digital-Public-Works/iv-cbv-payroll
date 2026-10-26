# Field descriptors for GET /api/admin/v1/schema. The
# vmi-admin portal builds its forms from this.
module AdminApi
  module Schema
    L = PartnerConfigLoader

    METHOD_LABELS = {
      "sftp" => "SFTP", "shared_email" => "Shared email", "encrypted_s3" => "Encrypted S3",
      "json" => "JSON", "webhook" => "Webhook", "unencrypted_s3" => "Unencrypted S3"
    }.freeze

    DESCRIPTIONS = {
      "timezone" => "IANA time zone, e.g. America/New_York",
      "domain" => "Subdomain used for host routing",
      "partner_identifier_name" => "Must be one of the application attributes",
      "weekly_report_recipients" => "Comma-separated email addresses",
      "validation_regex" => "Ruby regex, e.g. \\A\\d{8}\\z",
      "path_prefix" => "No leading /; blank means the root",
      "port" => "Defaults to 22",
      "endpoint" => "Test only",
      "force_path_style" => "Test only",
      "custom_headers" => "May carry auth tokens",
      "public_key" => "GPG public key"
    }.freeze

    USAGE_LABELS = { "invitation_attributes" => "Invitation", "landing_page_attributes" => "Landing page", "applicant_input_page" => "Applicant input page" }.freeze

    module_function

    def call
      {
        scalars: L::SETTINGS_ATTRS.map { |name| scalar(name, "settings") } +
          (L::CREDENTIAL_ATTRS - %w[partner_id]).map { |name| scalar(name, "credentials") },
        application_attribute_fields: L::APPLICATION_ATTRIBUTE_KEYS.map { |name| attribute_field(name) },
        usage_sections: L::ATTRIBUTE_USAGE_SECTIONS.keys.map { |name| { name: name, label: USAGE_LABELS.fetch(name, name.humanize) } },
        translations: { required_locales: %w[en es], required_keys: L::REQUIRED_TRANSLATION_KEYS, optional_keys: %w[shared.agency_acronym] },
        transmission_methods: L::VALID_TRANSMISSION_METHODS.map { |type| method_type(type) },
        reserved_names: (L::RESERVED_DOMAIN_PREFIXES | L::RESERVED_PARTNER_IDS)
      }
    end

    def scalar(name, partition)
      field = typed_field(name, PartnerConfig)
      field[:partition] = partition
      field[:required] = (L::REQUIRED_ATTRS | L::REQUIRED_CREDENTIAL_ATTRS).include?(name)
      case name
      when "pay_income_days_w2", "pay_income_days_gig" then field.merge!(type: "enum", enum: L::VALID_PAY_INCOME_DAYS)
      when "argyle_environment" then field.merge!(type: "enum", enum: L::VALID_ARGYLE_ENVIRONMENTS)
      end
      field.compact
    end

    def attribute_field(name)
      field = typed_field(name, PartnerApplicationAttribute)
      field[:required] = %w[name data_type].include?(name)
      field.merge!(type: "enum", enum: L::VALID_DATA_TYPES, default: "string") if name == "data_type"
      field.compact
    end

    def typed_field(name, model)
      column = model.columns_hash[name]
      type = case column&.type
             when :boolean then "boolean"
             when :integer then "integer"
             when :text then "text"
             else "string"
             end
      {
        name: name,
        label: name.humanize,
        type: type,
        default: model.column_defaults[name],
        description: DESCRIPTIONS[name]
      }
    end

    def method_type(type)
      required = L::REQUIRED_CREDENTIAL_KEYS.fetch(type, [])
      keys = (required + L::OPTIONAL_CREDENTIAL_KEYS.fetch(type, [])).uniq
      {
        method_type: type,
        label: METHOD_LABELS.fetch(type, type.humanize),
        keys: keys.map do |key|
          {
            key: key,
            required: required.include?(key),
            blank_allowed: L::BLANK_ALLOWED_KEYS.include?(key),
            encrypted: L::SECRET_CREDENTIAL_KEYS.include?(key),
            description: DESCRIPTIONS[key]
          }.compact
        end
      }
    end
  end
end
