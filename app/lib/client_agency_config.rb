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

  def client_agency_ids
    (@client_agencies || {}).keys
  end

  def [](client_agency_id)
    (@client_agencies || {})[client_agency_id]
  end

  def initialize(load_all_agency_configs)
    # This code runs during every boot of the app, including the migrations necessary top create the partner_configs table.
    # Skip if the table hasn't been created yet.
    # The partner application attributes are added last, so if they are not present, the db is missing tables needed to initialize from db configuration.
    return unless ActiveRecord::Base.connection.data_source_exists?(:partner_application_attributes)

    @client_agencies = PartnerConfig.all.each_with_object({}) do |config, h|
      next unless load_all_agency_configs ||
        (config.active_demo? && demo_mode?) ||
        (config.active_prod? && Rails.env.production?)
      h[config.partner_id] = ClientAgency.new(config)
    end

    validate_partner_application_attributes
  end

  # TODO: Possibly remove, this appears unused.
  # def self.client_agencies(load_all_agency_configs = false)
  #   self.client_agency_ids(load_all_agency_configs)
  # end

  private

  def validate_partner_application_attributes
    return unless @client_agencies.present?

    @client_agencies.each do |partner_id, agency|
      if agency.applicant_attributes.empty?
        message = "Partner #{partner_id} has no partner_application_attributes configured. " \
          "API metadata will be silently dropped and data retention will fail."
        Rails.logger.error(message)
        NewRelic::Agent.notice_error(StandardError.new(message)) if defined?(NewRelic::Agent)
      end
    end

    validate_partner_translations if ActiveRecord::Base.connection.data_source_exists?(:partner_translations)
  end

  REQUIRED_TRANSLATION_KEYS = %w[
      shared.agency_acronym
      shared.agency_full_name
      shared.header.cbv_flow_title
      shared.header.preheader
      shared.benefit
      shared.reporting_purpose
    ].freeze

  def validate_partner_translations
    return unless @client_agencies.present?

    @client_agencies.each do |partner_id, _agency|
      config = PartnerConfig.find_by(partner_id: partner_id)
      next unless config

      %w[en es].each do |locale|
        REQUIRED_TRANSLATION_KEYS.each do |base_key|
          full_key = "#{base_key}.#{partner_id}"
          has_db = PartnerTranslation.exists?(partner_config: config, locale: locale, key: full_key)
          has_locale = I18n.exists?(full_key, locale.to_sym)

          unless has_db || has_locale
            default_key = "#{base_key}.default"
            has_db_default = PartnerTranslation.exists?(partner_config: config, locale: locale, key: default_key)
            has_locale_default = I18n.exists?(default_key, locale.to_sym)

            unless has_db_default || has_locale_default
              message = "Partner #{partner_id} missing translation: #{full_key} (#{locale}) with no default fallback"
              Rails.logger.warn(message)
              NewRelic::Agent.notice_error(StandardError.new(message)) if defined?(NewRelic::Agent)
            end
          end
        end
      end
    end
  end

  public

  class ClientAgency
    attr_reader(*%i[
      id
      agency_name
      timezone
      agency_contact_website
      agency_domain
      authorized_emails
      default_origin
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
      transmission_method
      transmission_method_configuration
      weekly_report
      applicant_attributes
      generic_links_disabled
      report_customization_show_earnings_list
      require_applicant_information_on_invitation
      include_invitation_details_on_weekly_report
      state_name
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

      @transmission_method = partner_config.transmission_method

      @transmission_method_configuration = partner_config.partner_transmission_configs.each_with_object({}) do |txc, h|
        h[txc.key] = txc.value
      end.with_indifferent_access

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

      @require_applicant_information_on_invitation = partner_config.partner_application_attributes.exists?(required: true)
      @include_invitation_details_on_weekly_report = partner_config.respond_to?(:include_invitation_details_on_weekly_report) &&
        partner_config.include_invitation_details_on_weekly_report
      @state_name = partner_config.respond_to?(:state_name) ? partner_config.state_name : nil

      raise ArgumentError.new("Client Agency missing id") if @id.blank?
      raise ArgumentError.new("Client Agency #{@id} missing required attribute `timezone`") if @timezone.blank?
      raise ArgumentError.new("Client Agency #{@id} missing required attribute `name`") if @agency_name.blank?
      raise ArgumentError.new("Client Agency #{@id} invalid value for pay_income_days.w2") unless VALID_PAY_INCOME_DAYS.include?(@pay_income_days[:w2])
      raise ArgumentError.new("Client Agency #{@id} invalid value for pay_income_days.gig") unless VALID_PAY_INCOME_DAYS.include?(@pay_income_days[:gig])
      raise ArgumentError.new("Client Agency #{@id} missing required attribute `transmission_method`") if @transmission_method.blank?
    end

    def self.case_number(cbv_flow)
      cbv_flow.cbv_applicant.case_number.rjust(8, "0")
    end

    def pdf_filename(cbv_flow, time)
      time = time.in_time_zone(timezone)

      padded_case_number = cbv_flow.cbv_applicant.case_number.rjust(8, "0")
      "CBVPilot_#{padded_case_number}_" \
        "#{time.strftime('%Y%m%d')}_" \
        "Conf#{cbv_flow.confirmation_code}"
    end

    def format_timestamp(time)
      return nil if time.nil?

      time.in_time_zone(timezone).strftime("%m/%d/%Y %H:%M:%S")
    end
  end
end
