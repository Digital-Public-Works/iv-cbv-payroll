# Dev-only helper to spin up a fully-formed partner (config + transmission
# method + application attributes + DB translations) populated with realistic
# fake data).
#
#   bundle exec rake dev:partner:create
#   bundle exec rake "dev:partner:create[my_partner_id]"
#   bundle exec rake "dev:partner:destroy[my_partner_id]"
#   bundle exec rake dev:partner:list
#
# Copies a reference agency's translations onto a new partner so it renders
# everywhere — not just the handful of keys validated at boot. Agency-specific
# strings live in the locale files keyed by agency id, in two shapes:
#   1. suffix:  shared.agency_portal_name: { sandbox: "...", pa_dhs: "..." }
#   2. subtree: cbv.applicant_informations: { sandbox: { fields: {...} }, ... }
# We walk the loaded I18n tree for the reference agency and re-key its values for
# the new partner so db_translation finds them.
module DevPartnerTranslations
  module_function

  # => { locale_sym => { db_key => value } }
  def for_partner(partner_id, reference: "sandbox")
    I18n.backend.send(:init_translations) unless I18n.backend.initialized?
    I18n.backend.send(:translations).each_with_object({}) do |(locale, tree), out|
      collected = {}
      walk(tree, [], partner_id, reference.to_sym, collected)
      out[locale] = collected
    end
  rescue StandardError => e
    Rails.logger.warn("DevPartnerTranslations: could not copy reference translations: #{e.message}")
    {}
  end

  def walk(node, path, partner_id, ref, out)
    return unless node.is_a?(Hash)

    node.each do |key, value|
      if key == ref
        if value.is_a?(Hash)
          # subtree pattern: re-key sandbox.* leaves as <partner_id>.*
          leaves(value, []) { |sub, leaf| out[(path + [ partner_id ] + sub).join(".")] = leaf }
        elsif value.is_a?(String)
          # suffix pattern: store under the base key (db_translation strips the id)
          out[path.join(".")] = value
        end
      elsif value.is_a?(Hash)
        walk(value, path + [ key.to_s ], partner_id, ref, out)
      end
    end
  end

  def leaves(node, path, &blk)
    node.each do |k, v|
      v.is_a?(Hash) ? leaves(v, path + [ k.to_s ], &blk) : (blk.call(path + [ k.to_s ], v) if v.is_a?(String))
    end
  end
end

namespace :dev do
  namespace :partner do
    REQUIRED_PARTNER_TRANSLATIONS = ClientAgencyConfig::REQUIRED_TRANSLATION_KEYS
    # Prefix every generated string so faked text is obvious on screen.
    GENERATED_PREFIX = "DEV - "

    desc "Generate a new partner (with translations) populated with fake data"
    task :create, [ :partner_id ] => :environment do |_t, args|
      abort "Refusing to run in production." if Rails.env.production?
      require "faker"

      partner_id = (args[:partner_id].presence || "dev_#{Faker::Color.color_name}_#{SecureRandom.hex(2)}")
        .downcase.gsub(/[^a-z0-9_]/, "_")

      if PartnerConfig.exists?(partner_id: partner_id)
        abort "Partner '#{partner_id}' already exists. Pass a different id or destroy it first."
      end

      # Use an obviously-fictional "place" so a generated partner can't be mistaken
      # for a real agency (e.g. "Naboo Department of Health", not "Iowa ...").
      realm = Faker::Movies::StarWars.planet
      agency_kind = [ "Department of Human Services", "Department of Economic Security",
                      "Department of Health", "Family Assistance Administration" ].sample
      full_name = "#{realm} #{agency_kind}"
      acronym = full_name.scan(/\b[A-Z]/).join.presence || Faker::Alphanumeric.alpha(number: 3).upcase

      result = ActiveRecord::Base.transaction do
        config = PartnerConfig.create!(
          partner_id: partner_id,
          name: "#{GENERATED_PREFIX}#{full_name}",
          state_name: realm,
          timezone: %w[America/New_York America/Chicago America/Denver America/Los_Angeles America/Phoenix].sample,
          website: "https://#{partner_id.tr('_', '-')}.example.gov",
          domain: partner_id.tr("_", "-"),
          argyle_environment: "sandbox",
          partner_identifier_name: "case_number",
          pay_income_days_w2: 90,
          pay_income_days_gig: 90,
          invitation_valid_days_default: 14,
          # Active + enabled in every environment so it shows up wherever you look.
          active_demo: true,
          active_prod: true,
          staff_portal_enabled: true,
          generic_links_enabled: true,
          invitation_links_enabled: true
        )

        config.partner_transmission_methods.create!(method_type: :shared_email)

        [
          { name: "case_number", required: true, show_on_caseworker_report: true },
          { name: "first_name", required: false },
          { name: "last_name", required: false }
        ].each do |attrs|
          config.partner_application_attributes.create!(
            name: attrs[:name],
            description: attrs[:name].humanize,
            data_type: :string,
            required: attrs.fetch(:required, false),
            show_on_caseworker_report: attrs.fetch(:show_on_caseworker_report, false)
          )
        end

        # Brand the identity strings so the partner is visibly distinct...
        branded = {
          "shared.agency_acronym" => acronym,
          "shared.agency_full_name" => full_name,
          "shared.agency_portal_name" => "#{full_name} Portal",
          "shared.header.cbv_flow_title" => "#{acronym} Income Verification",
          "shared.header.preheader" => Faker::Company.catch_phrase,
          "cbv.entries.show.checkbox" => "I agree to share my income with #{acronym} (#{Faker::Company.catch_phrase})"
        }
        # ...and copy everything else from the reference agency so it renders
        # everywhere without tripping the "Missing agency translation" guard.
        # Every value is prefixed so any text on screen is identifiably generated.
        copied = DevPartnerTranslations.for_partner(partner_id, reference: "sandbox")
        I18n.available_locales.each do |locale|
          (copied[locale] || {}).merge(branded).each do |key, value|
            next unless value.is_a?(String) && value.present?
            config.partner_translations.create!(locale: locale.to_s, key: key, value: "#{GENERATED_PREFIX}#{value}")
          end
        end

        # Service account user + API token — the "user token" you normally POST
        # with in Bruno against /api/v1/invitations.
        user = User.create!(
          client_agency_id: partner_id,
          email: "#{partner_id}-svc@example.gov",
          is_service_account: true
        )
        api_token = user.api_access_tokens.create!.access_token

        # Create an invitation directly (same outcome as POST /api/v1/invitations),
        # without sending email or emitting tracking events.
        case_number = Faker::Number.number(digits: 8).to_s
        invitation = CbvFlowInvitation.create!(
          client_agency_id: partner_id,
          user: user,
          language: "en",
          email_address: user.email,
          cbv_applicant_attributes: {
            client_agency_id: partner_id,
            partner_identifier: case_number,
            custom_attributes: { "first_name" => Faker::Name.first_name, "last_name" => Faker::Name.last_name }
          }
        )

        [ config, api_token, invitation ]
      end

      partner, api_token, invitation = result

      # The running dev server doesn't need this (it reloads configs lazily); it
      # only refreshes the singleton within *this* rake process.
      ClientAgencyConfig.reset!

      sub = "http://#{partner.domain}.#{ENV.fetch('DOMAIN_NAME', 'localhost')}:3000"
      puts <<~SUMMARY

        Created partner '#{partner.partner_id}' — #{partner.name} (#{acronym})
          subdomain:    #{partner.domain}
          attributes:   #{partner.partner_application_attributes.pluck(:name).join(', ')}
          translations: #{partner.partner_translations.count} rows across #{I18n.available_locales.join(', ')}

        Visit it now (no reboot needed). Served on the partner subdomain, exactly
        like the seeded partners — DOMAIN_NAME=localhost and browsers resolve
        *.localhost to 127.0.0.1, so no /etc/hosts entry is needed:
          landing page:      #{sub}/
          caseworker portal: #{sub}/#{partner.partner_id}
          generic link:      #{sub}/cbv/links/#{partner.partner_id}
          tokenized flow:    #{sub}/start/#{invitation.auth_token}

        API access (same as POSTing to /api/v1/invitations in Bruno):
          token: #{api_token}
          curl -X POST #{sub}/api/v1/invitations \\
            -H "Authorization: Bearer #{api_token}" \\
            -H "Content-Type: application/json" \\
            -d '{"language":"en","custom_attributes":{"case_number":"12345678"}}'

        Remove it with:
          bundle exec rake "dev:partner:destroy[#{partner.partner_id}]"
      SUMMARY
    end

    desc "Destroy a partner created for dev validation"
    task :destroy, [ :partner_id ] => :environment do |_t, args|
      abort "Refusing to run in production." if Rails.env.production?
      partner_id = args[:partner_id].presence or abort "Usage: rake \"dev:partner:destroy[partner_id]\""

      config = PartnerConfig.find_by(partner_id: partner_id) or abort "Partner '#{partner_id}' not found."

      # Delete children explicitly: PartnerConfig#destroy is unusable here because
      # its `has_many :partner_transmission_configs, dependent: :destroy` points at
      # a column (partner_config_id) that doesn't exist on that table — those
      # configs hang off partner_transmission_methods instead.
      ActiveRecord::Base.transaction do
        # Flow data created by actually using the partner, deleted leaf-first to
        # satisfy FK constraints (webhook_events -> payroll_accounts -> cbv_flows;
        # cbv_flows -> cbv_flow_invitations). delete_all is used because the AR
        # cascade is incomplete (PayrollAccount has_many :webhook_events has no
        # dependent: :destroy).
        flow_ids = CbvFlow.where(client_agency_id: partner_id).pluck(:id)
        payroll_account_ids = PayrollAccount.where(cbv_flow_id: flow_ids).pluck(:id)
        WebhookEvent.where(payroll_account_id: payroll_account_ids).delete_all
        PayrollAccount.where(id: payroll_account_ids).delete_all
        CbvFlowTransmission.where(cbv_flow_id: flow_ids).delete_all
        CbvFlow.where(id: flow_ids).delete_all
        CbvFlowInvitation.where(client_agency_id: partner_id).delete_all
        CbvApplicant.where(client_agency_id: partner_id).delete_all

        user_ids = User.where(client_agency_id: partner_id).pluck(:id)
        ApiAccessToken.where(user_id: user_ids).delete_all
        User.where(id: user_ids).delete_all

        # Partner config + children (see note above re: PartnerConfig#destroy).
        method_ids = config.partner_transmission_methods.pluck(:id)
        PartnerTransmissionConfig.where(partner_transmission_method_id: method_ids).delete_all
        config.partner_transmission_methods.delete_all
        config.partner_application_attributes.delete_all
        config.partner_translations.delete_all
        config.delete
      end

      ClientAgencyConfig.reset!
      puts "Destroyed partner '#{partner_id}'."
    end

    desc "List configured partners"
    task list: :environment do
      printf("%-24s %-40s %s\n", "partner_id", "name", "domain")
      PartnerConfig.order(:partner_id).each do |c|
        printf("%-24s %-40s %s\n", c.partner_id, c.name, c.domain)
      end
    end
  end
end
