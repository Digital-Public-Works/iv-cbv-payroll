require "yaml"
require_relative "non_production_accessible"

class ClientAgencyConfig
  include NonProductionAccessible

  # These are the only supported number of days we allow an agency to define in
  # the `pay_income_days` configuration option.
  #
  # Every value in this array must have a corresponding partial webhook
  # subscription in ArgyleWebhooksManager in order to properly allow the user
  # to continue as soon as that amount of data has synced.
  #
  # If you add a new entry to this list, also search for
  # 'ninety_days'/'six_months' to see other places you will need to customize.
  VALID_PAY_INCOME_DAYS = [ 90, 182 ]

  # How long a hydrated agency stays cached before it is reloaded from the
  # database. Bounds how stale a config can be: changes made to partner_configs
  # while the app is running are picked up within this window without a restart.
  # In development the effective TTL is 0 so edits show up immediately (see
  # #cache_ttl_seconds).
  CACHE_TTL_SECONDS = 10.minutes.to_i

  def self.instance
    @instance ||= new(Rails.env.development? || Rails.env.test?)
  end

  def self.reset!
    @instance = nil
  end

  def self.[](client_agency_id)
    instance[client_agency_id]
  end

  def self.client_agency_ids(load_all_agency_configs = false)
    instance.client_agency_ids
  end

  def initialize(load_all_agency_configs)
    @load_all_agency_configs = load_all_agency_configs
    # Configs are loaded lazily, per-agency, the first time each one is requested
    # (see #[]). Nothing is loaded at boot. Each cache holds timestamped entries
    # that expire after CACHE_TTL_SECONDS so DB changes are picked up at runtime.
    # @agencies caches hydrated agencies by partner_id; @domain_index caches
    # resolved domain => partner_id lookups.
    @agencies = {}
    @domain_index = {}
  end

  # Lazily loads and caches a single agency by partner_id, based on the
  # client_agency_id present in the requested URL. The cached entry is reloaded
  # from the database once it is older than CACHE_TTL_SECONDS, so edits to the
  # partner config (or a partner being deactivated/removed) are reflected within
  # that window without a restart.
  #
  # Returns nil when the partner does not exist, is not active in this
  # environment, or fails hard validation (in which case a warning is logged so a
  # single broken partner can't crash the request). Misses are not cached.
  def [](client_agency_id)
    return nil if client_agency_id.blank?

    entry = @agencies[client_agency_id]
    return entry[:agency] if entry && fresh?(entry)
    return nil unless db_ready?

    config = PartnerConfig.find_by(partner_id: client_agency_id)
    unless config && active_in_current_environment?(config)
      @agencies.delete(client_agency_id)
      return nil
    end

    agency = build_agency(config)
    if agency.nil?
      @agencies.delete(client_agency_id)
      return nil
    end

    @agencies[client_agency_id] = { agency: agency, loaded_at: now }
    agency
  end

  # Resolves an agency by its configured subdomain/host slug (e.g. "pa" or
  # "pa.example.com"). A single indexed lookup (cached with the same TTL as #[]),
  # then delegates to #[] for hydration.
  def find_by_domain(domain)
    return nil if domain.blank?
    return nil unless db_ready?

    entry = @domain_index[domain]
    if entry && fresh?(entry)
      partner_id = entry[:partner_id]
    else
      config = PartnerConfig.find_by(domain: domain)
      unless config && active_in_current_environment?(config)
        @domain_index.delete(domain)
        return nil
      end

      partner_id = config.partner_id
      @domain_index[domain] = { partner_id: partner_id, loaded_at: now }
    end

    self[partner_id]
  end

  def client_agency_ids
    active_partner_configs.pluck(:partner_id)
  end

  # Eagerly validates every active partner config WITHOUT caching them for
  # serving, so a single boot-time pass surfaces misconfiguration early. Logs (but
  # does not raise on) any partner that fails to construct or is missing required
  # configuration, so one bad partner can't take down boot. Run from the
  # validate_partner_configs initializer; serving stays lazy via #[].
  def validate_all
    return unless db_ready?

    active_partner_configs.find_each { |config| validate_config(config) }
  end

  private

  # A cache entry is fresh until it is older than the TTL, after which the next
  # lookup reloads it from the database.
  def fresh?(entry)
    now - entry[:loaded_at] < cache_ttl_seconds
  end

  # Effective cache TTL. In development it is 0 so every lookup reloads from the
  # database and config edits are reflected immediately; elsewhere it is the full
  # CACHE_TTL_SECONDS.
  def cache_ttl_seconds
    Rails.env.development? ? 0 : CACHE_TTL_SECONDS
  end

  # Monotonic clock (seconds) so cache expiry is unaffected by wall-clock changes.
  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def active_partner_configs
    return PartnerConfig.none unless db_ready?

    if @load_all_agency_configs
      PartnerConfig.all
    elsif demo_mode?
      PartnerConfig.where(active_demo: true)
    elsif Rails.env.production?
      PartnerConfig.where(active_prod: true)
    else
      PartnerConfig.none
    end
  end

  def active_in_current_environment?(config)
    @load_all_agency_configs ||
      (config.active_demo? && demo_mode?) ||
      (config.active_prod? && Rails.env.production?)
  end

  # Builds and validates a single agency for serving. A hard-validation failure
  # is converted to a logged warning + nil rather than a raised exception, so a
  # broken partner config yields a 404 (route won't match) instead of a 500.
  def build_agency(config)
    agency = ClientAgency.new(config)
    warn_on_soft_validation(config, agency)
    agency
  rescue ArgumentError => e
    report_partner_error("Partner #{config.partner_id} failed validation and is unavailable: #{e.message}")
    nil
  end

  # Boot-time counterpart to #build_agency: surfaces both hard and soft problems
  # as log warnings without building anything for serving.
  def validate_config(config)
    agency = ClientAgency.new(config)
    warn_on_soft_validation(config, agency)
  rescue ArgumentError => e
    report_partner_error("Partner #{config.partner_id} failed validation: #{e.message}")
  end

  def warn_on_soft_validation(config, agency)
    if agency.applicant_attributes.empty?
      report_partner_error("Partner #{config.partner_id} has no partner_application_attributes configured. " \
        "API metadata will be silently dropped and data retention will fail.")
    end

    validate_partner_translations(config)
  end

  REQUIRED_TRANSLATION_KEYS = %w[
      shared.agency_full_name
      shared.header.cbv_flow_title
      shared.header.preheader
    ].freeze

  OPTIONAL_TRANSLATION_KEYS = %w[
      shared.agency_acronym
    ].freeze

  def validate_partner_translations(config)
    return unless defined?(::PartnerTranslation) &&
      ActiveRecord::Base.connection.data_source_exists?(:partner_translations)

    partner_id = config.partner_id
    %w[en es].each do |locale|
      REQUIRED_TRANSLATION_KEYS.each do |base_key|
        full_key = "#{base_key}.#{partner_id}"
        has_db = ::PartnerTranslation.exists?(partner_config: config, locale: locale, key: base_key) ||
          ::PartnerTranslation.exists?(partner_config: config, locale: locale, key: full_key)
        has_locale = I18n.exists?(full_key, locale.to_sym)
        next if has_db || has_locale

        default_key = "#{base_key}.default"
        has_db_default = ::PartnerTranslation.exists?(partner_config: config, locale: locale, key: default_key)
        has_locale_default = I18n.exists?(default_key, locale.to_sym)
        next if has_db_default || has_locale_default

        report_partner_warning("Partner #{partner_id} missing translation: #{full_key} (#{locale}) with no default fallback")
      end
    end
  end

  # Guards the lazy DB lookups: the table/column checks tolerate boot-time and
  # rake-task scenarios where the schema isn't ready yet (migrations, db:create).
  def db_ready?
    ActiveRecord::Base.connection.data_source_exists?(:partner_application_attributes) &&
      ActiveRecord::Base.connection.column_exists?(:partner_configs, :partner_identifier_name)
  rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad, ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid
    false
  end

  def report_partner_error(message)
    Rails.logger.error(message)
    NewRelic::Agent.notice_error(StandardError.new(message)) if defined?(NewRelic::Agent)
  end

  def report_partner_warning(message)
    Rails.logger.warn(message)
    NewRelic::Agent.notice_error(StandardError.new(message)) if defined?(NewRelic::Agent)
  end

  public

  class ClientAgency
    TransmissionMethodEntry = Struct.new(:method, :configuration, keyword_init: true)

    attr_reader(*%i[
      id
      agency_name
      timezone
      agency_contact_website
      agency_domain
      authorized_emails
      default_origin
      include_full_ssn
      include_direct_deposit_last_4
      invitation_valid_days
      logo_path
      logo_square_path
      pay_income_days
      pinwheel_api_token
      pinwheel_environment
      pilot_ended
      argyle_environment
      staff_portal_enabled
      sso
      transmission_methods
      weekly_report
      applicant_attributes
      generic_links_disabled
      report_customization_show_earnings_list
      require_applicant_information_on_invitation
      include_invitation_details_on_weekly_report
      include_paystubs
      state_name
      partner_identifier_name
    ])

    def initialize(partner_config)
      raise ArgumentError.new("Failed to initialize ClientAgency with null partner config") unless partner_config.present?

      # TODO: may eventually want to rename @id.
      @id = partner_config.partner_id
      @timezone = partner_config.timezone
      @agency_name = partner_config.name
      @agency_contact_website = partner_config.website
      @agency_domain = partner_config.domain
      @default_origin = partner_config.default_origin
      @invitation_valid_days = partner_config.invitation_valid_days_default
      @logo_path = partner_config.logo_path
      @pay_income_days = { w2: partner_config.pay_income_days_w2, gig: partner_config.pay_income_days_gig }
      @pilot_ended = partner_config.pilot_ended
      @argyle_environment = partner_config.argyle_environment || "sandbox"

      @transmission_methods = partner_config.partner_transmission_methods.map do |ptm|
        config = ptm.partner_transmission_configs.each_with_object({}) do |txc, h|
          h[txc.key] = txc.value
        end.with_indifferent_access

        TransmissionMethodEntry.new(method: ptm.method_type, configuration: config)
      end

      @transmission_methods.each do |entry|
        method_type = entry.method.to_sym
        next unless TransmissionFilename::EXTENSIONS.key?(method_type)
        # remote_directory_for validates that path_prefix is valid for method_type
        TransmissionFilename.remote_directory_for(
          method_type: method_type,
          remote_directory: entry.configuration["path_prefix"]
        )
      rescue ArgumentError => e
        raise ArgumentError.new("Client Agency #{@id}: #{e.message}")
      end

      @staff_portal_enabled = partner_config.staff_portal_enabled
      @weekly_report = {
        "enabled" => partner_config.weekly_report_enabled,
        "recipient" => partner_config.weekly_report_recipients,
        "report_variant" => partner_config.weekly_report_variant
      }

      @applicant_attributes = partner_config.partner_application_attributes.each_with_object({}) do |attr, h|
        h[attr.name] = attr
      end.with_indifferent_access

      @report_customization_show_earnings_list = partner_config.report_customization_show_earnings_list
      @generic_links_disabled = !partner_config.generic_links_enabled
      @invitation_links_enabled = partner_config.invitation_links_enabled
      @include_full_ssn = partner_config.include_full_ssn
      @include_direct_deposit_last_4 = partner_config.include_direct_deposit_last_4


      @require_applicant_information_on_invitation = partner_config.partner_application_attributes.exists?(required: true)
      @include_invitation_details_on_weekly_report = partner_config.respond_to?(:include_invitation_details_on_weekly_report) &&
        partner_config.include_invitation_details_on_weekly_report
      @include_paystubs = partner_config.respond_to?(:include_paystubs) &&
        partner_config.include_paystubs
      @state_name = partner_config.respond_to?(:state_name) ? partner_config.state_name : nil
      @partner_identifier_name = partner_config.partner_identifier_name

      raise ArgumentError.new("Client Agency missing id") if @id.blank?
      raise ArgumentError.new("Client Agency #{@id} missing required attribute `timezone`") if @timezone.blank?
      raise ArgumentError.new("Client Agency #{@id} missing required attribute `name`") if @agency_name.blank?
      raise ArgumentError.new("Client Agency #{@id} invalid value for pay_income_days.w2") unless VALID_PAY_INCOME_DAYS.include?(@pay_income_days[:w2])
      raise ArgumentError.new("Client Agency #{@id} invalid value for pay_income_days.gig") unless VALID_PAY_INCOME_DAYS.include?(@pay_income_days[:gig])
      raise ArgumentError.new("Client Agency #{@id} missing required attribute `partner_identifier_name`") if @partner_identifier_name.blank?
      raise ArgumentError.new("Client Agency #{@id} must have at least one transmission method configured") if @transmission_methods.empty?
    end

    # Returns true if this agency has the given transmission method configured.
    def has_transmission_method?(method_type)
      @transmission_methods.any? { |tm| tm.method == method_type.to_s }
    end

    # Returns the configuration hash for a specific transmission method type.
    def transmission_configuration_for(method_type)
      entry = @transmission_methods.find { |tm| tm.method == method_type.to_s }
      entry&.configuration || {}.with_indifferent_access
    end

    def self.case_number(cbv_flow)
      cbv_flow.cbv_applicant.case_number.rjust(8, "0")
    end

    def format_timestamp(time)
      return nil if time.nil?

      time.in_time_zone(timezone).strftime("%m/%d/%Y %H:%M:%S")
    end
  end
end
