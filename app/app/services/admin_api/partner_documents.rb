# Reading a partner as the two documents the admin API speaks and its version token.
module AdminApi
  module PartnerDocuments
    module_function

    # partner_configs.updated_at moves on every change made through the loader
    # (it touches the row when only a section changed), so it serves as the
    # optimistic-concurrency token. Same format as GET /partners.
    def version(partner_config)
      partner_config.updated_at.iso8601(6)
    end

    # Both documents, secrets masked as $ENCRYPTED.
    def detail(partner_config)
      docs = PartnerConfigLoader.export(partner_config.partner_id)
      {
        partner_id: partner_config.partner_id,
        updated_at: version(partner_config),
        settings: docs[:settings],
        credentials: docs[:credentials]
      }
    end

    # The documents as files, named and serialized as rake partner_config:export
    # writes them. include_secrets decrypts encrypted values (backups only).
    def export_files(partner_id, include_secrets: false)
      docs = PartnerConfigLoader.export(partner_id, include_secrets: include_secrets)
      {
        partner_id: partner_id,
        files: {
          settings: { filename: "#{partner_id}.settings.yml", content: docs[:settings].to_yaml },
          credentials: { filename: "#{partner_id}.credentials.#{Rails.env}.yml", content: docs[:credentials].to_yaml }
        }
      }
    end

    # Masked documents: the base a partial change is merged onto. Masked secrets
    # in it are kept by the loader (keep_stored_secrets!).
    def current(partner_id)
      PartnerConfigLoader.export(partner_id)
    end

    # Decrypted documents for diffing only; never returned.
    def current_with_secrets(partner_id)
      PartnerConfigLoader.export(partner_id, include_secrets: true)
    end
  end
end
