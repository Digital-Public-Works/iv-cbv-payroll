module AdminApi
  class PartnerWrites
    SETTINGS_SECTION_KEYS = {
      "application_attributes" => :application_attributes,
      "translations" => :translations
    }.merge(PartnerConfigLoader::ATTRIBUTE_USAGE_SECTIONS.keys.index_with { :attribute_usages }).freeze

    # existed: whether the partner was already there before this call.
    Result = Struct.new(:loader, :diff, :existed, keyword_init: true)

    def initialize(settings_writable: Config.settings_writable?)
      @settings_writable = settings_writable
    end

    # -------------------------------------------------------------------------
    # Partial changes
    # -------------------------------------------------------------------------

    # Builds and validates the partner's config with `partial` merged in. Each
    # supplied scalar replaces that field; each supplied section replaces the
    # whole section.
    def candidate(partner_config, partial)
      settings, credentials = documents_of(partial)
      base = PartnerDocuments.current(partner_config.partner_id)
      loader = PartnerConfigLoader.from_documents(base[:settings].merge(settings), base[:credentials].merge(credentials))
      loader.keep_stored_secrets!(partner_config)
      loader.validate!
    end

    def diff(partner_config, loader)
      before = PartnerDocuments.current_with_secrets(partner_config.partner_id)
      ConfigDiff.call(before, { settings: loader.settings_data, credentials: loader.credentials_data }, kept: loader.kept_secrets)
    end

    # PATCH: scalars and settings sections. Transmission methods go through
    # #replace_transmission_methods.
    def update(partner_config, partial, expected_version:)
      settings, credentials = documents_of(partial)
      raise Errors::Forbidden, settings_read_only_message if settings.any? && !@settings_writable
      raise Errors::BadRequest, "Use PUT …/transmission_methods to change transmission methods" if credentials.key?("transmission_methods")
      if settings.key?("partner_id") && settings["partner_id"].to_s != partner_config.partner_id
        raise Errors::BadRequest, "partner_id cannot be changed"
      end

      loader = candidate(partner_config, partial)
      raise Errors::Invalid, loader unless loader.valid?

      scalar_keys = (settings.keys - SETTINGS_SECTION_KEYS.keys) + credentials.keys
      sections = settings.keys.filter_map { |k| SETTINGS_SECTION_KEYS[k] }.uniq
      write(partner_config, expected_version) { loader.apply_scoped!(scalar_keys: scalar_keys, sections: sections) }
      Result.new(loader: loader)
    end

    def replace_transmission_methods(partner_config, methods, expected_version:)
      raise Errors::BadRequest, "transmission_methods must be a list" unless methods.is_a?(Array)

      loader = candidate(partner_config, { "credentials" => { "transmission_methods" => methods } })
      raise Errors::Invalid, loader unless loader.valid?

      write(partner_config, expected_version) { loader.apply_scoped!(scalar_keys: [], sections: %i[transmission_methods]) }
      Result.new(loader: loader)
    end

    # -------------------------------------------------------------------------
    # Whole partners
    # -------------------------------------------------------------------------

    def create(settings, credentials)
      raise Errors::Forbidden, "Partners are created in this environment only by promotion" unless @settings_writable
      raise Errors::BadRequest, "settings and credentials must be mappings" unless settings.is_a?(Hash) && credentials.is_a?(Hash)
      if PartnerConfig.exists?(partner_id: settings["partner_id"].to_s)
        raise Errors::Conflict, "Partner '#{settings['partner_id']}' already exists"
      end

      loader = PartnerConfigLoader.from_documents(settings, credentials).validate!
      raise Errors::Invalid, loader unless loader.valid?

      loader.apply!
      Result.new(loader: loader)
    end

    # Import config: a settings document, a credentials document, or both, as
    # YAML. A missing document is taken from the database. Returns the diff;
    # applies it unless dry_run.
    def import(settings_yaml:, credentials_yaml:, expected_version:, confirm_deletes:, dry_run:)
      settings_doc = parse_yaml(settings_yaml, "settings")
      credentials_doc = parse_yaml(credentials_yaml, "credentials")
      raise Errors::BadRequest, "Supply a settings document, a credentials document, or both" if settings_doc.nil? && credentials_doc.nil?
      raise Errors::Forbidden, settings_read_only_message if settings_doc && !@settings_writable

      partner_id = (settings_doc || credentials_doc)["partner_id"].to_s
      raise Errors::BadRequest, "The file has no partner_id" if partner_id.blank?
      existing = PartnerConfig.find_by(partner_id: partner_id)
      raise Errors::Forbidden, "Partners are created in this environment only by promotion" if existing.nil? && !@settings_writable
      if existing.nil? && (settings_doc.nil? || credentials_doc.nil?)
        raise Errors::BadRequest, "Partner '#{partner_id}' doesn't exist here yet, so both documents are needed"
      end

      base = existing && PartnerDocuments.current(partner_id)
      loader = PartnerConfigLoader.from_documents(settings_doc || base[:settings], credentials_doc || base[:credentials])
      loader.keep_stored_secrets!(existing)
      loader.validate!

      before = existing ? PartnerDocuments.current_with_secrets(partner_id) : {}
      diff = ConfigDiff.call(before, { settings: loader.settings_data, credentials: loader.credentials_data }, kept: loader.kept_secrets)
      result = Result.new(loader: loader, diff: diff, existed: existing.present?)
      return result if dry_run

      raise Errors::Invalid, loader unless loader.valid?
      raise Errors::UnconfirmedDeletes, diff[:deletes] if diff[:deletes].any? && !confirm_deletes

      apply = lambda do
        if settings_doc && credentials_doc then loader.apply!
        elsif settings_doc then loader.apply_settings!
        else loader.apply_scoped!(scalar_keys: PartnerConfigLoader::CREDENTIAL_ATTRS, sections: %i[transmission_methods])
        end
      end
      existing ? write(existing, expected_version, &apply) : apply.call
      result
    end

    # Prod only: apply demo's settings. An existing partner keeps its prod credentials; a new one needs them.
    def promote_settings(partner_id, settings, credentials:, expected_version:)
      raise Errors::BadRequest, "settings must be a mapping" unless settings.is_a?(Hash)
      raise Errors::BadRequest, "partner_id in the settings does not match the URL" unless settings["partner_id"].to_s == partner_id

      existing = PartnerConfig.find_by(partner_id: partner_id)
      if existing
        loader = PartnerConfigLoader.from_documents(settings, PartnerDocuments.current(partner_id)[:credentials])
        loader.keep_stored_secrets!(existing)
      else
        raise Errors::BadRequest, "Partner '#{partner_id}' is new here: its credentials are required" unless credentials.is_a?(Hash)
        loader = PartnerConfigLoader.from_documents(settings, credentials)
      end
      loader.validate!
      raise Errors::Invalid, loader unless loader.valid?

      if existing
        write(existing, expected_version) { loader.apply_settings! }
      else
        loader.apply!
      end
      Result.new(loader: loader)
    end

    private

    def settings_read_only_message
      "Settings are read-only in this environment; they change only by promotion from demo"
    end

    def documents_of(partial)
      partial = partial.to_h.stringify_keys
      settings = partial["settings"] || {}
      credentials = partial["credentials"] || {}
      raise Errors::BadRequest, "settings and credentials must be mappings" unless settings.is_a?(Hash) && credentials.is_a?(Hash)
      [ settings.stringify_keys, credentials.stringify_keys ]
    end

    def parse_yaml(raw, label)
      return nil if raw.blank?
      doc = YAML.safe_load(raw, permitted_classes: [ Symbol ])
      raise Errors::BadRequest, "The #{label} document must be a mapping" unless doc.is_a?(Hash)
      doc.stringify_keys
    rescue Psych::SyntaxError => e
      raise Errors::BadRequest, "Errors::Invalid YAML in the #{label} document: #{e.message}"
    end

    # Locks the partner row, checks nobody changed it since the caller read it,
    # and applies.
    def write(partner_config, expected_version)
      PartnerConfig.transaction do
        partner_config.lock!
        unless expected_version.to_s == PartnerDocuments.version(partner_config)
          raise Errors::Conflict, "The partner changed since it was read (updated_at no longer matches)"
        end
        yield
      end
    end
  end
end
