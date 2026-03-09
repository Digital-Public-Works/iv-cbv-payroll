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
    @client_agencies.keys
  end

  def [](client_agency_id)
    @client_agencies[client_agency_id]
  end

  # load all configuration files in the configuration directory passed in if load_all_agency_configs is true,
  # otherwise load configurations where the environment variable for 'active' is set to true
  def initialize_yaml(config_path, load_all_agency_configs)
    @client_agencies = Dir.glob(File.join(config_path, "*.yml"))
     .each_with_object({}) do |path, h|
      data = load_yaml(path)
      # load all in dev, otherwise load only if the 'active' property is true for the env (see agency config file)
      next unless load_all_agency_configs || ActiveModel::Type::Boolean.new.cast(data["active"])

      puts "LOADED AGENCY #{data["id"]}"
      id = data["id"]
      h[id] = ClientAgency.new(data)
    end
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
  end

  def load_yaml(path)
    template = ERB.new(File.read(path))
    YAML.safe_load(template.result(binding))
  end

  # TODO: abstract this
  # def self.client_agencies(load_all_agency_configs = false)
  #   self.client_agency_ids(load_all_agency_configs)
  # end

  class ClientAgency
    attr_reader(*%i[
      id
      agency_name
      timezone
      agency_contact_website
      agency_domain
      authorized_emails
      caseworker_feedback_form
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
    ])

    def initialize_yaml(yaml)
      @id = yaml["id"]
      @timezone = yaml["timezone"]
      @agency_name = yaml["agency_name"]
      @agency_contact_website = yaml["agency_contact_website"]
      @agency_domain = yaml["agency_domain"]
      @authorized_emails = yaml["authorized_emails"] || ""
      @caseworker_feedback_form = yaml["caseworker_feedback_form"]
      @default_origin = yaml["default_origin"]
      @invitation_valid_days = yaml["invitation_valid_days"]
      @logo_path = yaml["logo_path"]
      @logo_square_path = yaml["logo_square_path"]
      @pay_income_days = yaml.fetch("pay_income_days", { w2: 90, gig: 90 }).symbolize_keys
      @pinwheel_environment = yaml["pinwheel"]["environment"] || "sandbox"
      @pilot_ended = yaml["pilot_ended"] || false
      @argyle_environment = yaml["argyle"]["environment"] || "sandbox"
      @transmission_method = yaml["transmission_method"]
      @transmission_method_configuration = yaml["transmission_method_configuration"]
      @staff_portal_enabled = yaml["staff_portal_enabled"]
      @sso = yaml["sso"]
      @weekly_report = yaml["weekly_report"]
      @applicant_attributes = yaml["applicant_attributes"] || {}
      @report_customization_show_earnings_list = !!yaml["report_customization_show_earnings_list"]
      @generic_links_disabled = yaml["generic_links_disabled"]
      @require_applicant_information_on_invitation = yaml["require_applicant_information_on_invitation"] || false

      raise ArgumentError.new("Client Agency missing id") if @id.blank?
      raise ArgumentError.new("Client Agency #{@id} missing required attribute `timezone`") if @timezone.blank?
      raise ArgumentError.new("Client Agency #{@id} missing required attribute `agency_name`") if @agency_name.blank?
      raise ArgumentError.new("Client Agency #{@id} invalid value for pay_income_days.w2") unless VALID_PAY_INCOME_DAYS.include?(@pay_income_days[:w2])
      raise ArgumentError.new("Client Agency #{@id} invalid value for pay_income_days.gig") unless VALID_PAY_INCOME_DAYS.include?(@pay_income_days[:gig])
      raise ArgumentError.new("Client Agency #{@id} missing required attribute `transmission_method`") if @transmission_method.blank?
    end

    def initialize(partner_config)
      raise ArgumentError.new("Failed to initialize ClientAgency with null partner config") unless partner_config.present?

      # NEXT STEPS
      # Count the parameters assigned & compare to the Asana.

      # TODO: may eventually want to rename @id.
      @id = partner_config.partner_id
      @timezone = partner_config.timezone
      @agency_name = partner_config.name
      @agency_contact_website = partner_config.website
      @agency_domain = partner_config.domain
      # @authorized_emails = yaml["authorized_emails"] || ""
      # @caseworker_feedback_form = yaml["caseworker_feedback_form"]
      @default_origin = partner_config.default_origin
      @invitation_valid_days = partner_config.invitation_valid_days_default
      @logo_path = partner_config.logo_path
      # @logo_square_path = yaml["logo_square_path"]
      @pay_income_days = { w2: partner_config.pay_income_days_w2, gig: partner_config.pay_income_days_gig }
      # @pinwheel_environment = yaml["pinwheel"]["environment"] || "sandbox"
      @pilot_ended = partner_config.pilot_ended
      # @argyle_environment = yaml["argyle"]["environment"] || "sandbox"
      @argyle_environment = partner_config.argyle_environment || "sandbox"

      # TODO
      @transmission_method = partner_config.transmission_method

      # TODO, load from the linked object
      # @transmission_method_configuration = partner_config.partner_transmission_config
      @transmission_method_configuration = partner_config.partner_transmission_configs.each_with_object({}) do |txc, h|
        h[txc.key] = txc.value
      end.with_indifferent_access

      @staff_portal_enabled = partner_config.staff_portal_enabled
      # @sso = yaml["sso"]
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

      raise ArgumentError.new("Client Agency missing id") if @id.blank?
      raise ArgumentError.new("Client Agency #{@id} missing required attribute `timezone`") if @timezone.blank?
      raise ArgumentError.new("Client Agency #{@id} missing required attribute `name`") if @agency_name.blank?
      raise ArgumentError.new("Client Agency #{@id} invalid value for pay_income_days.w2") unless VALID_PAY_INCOME_DAYS.include?(@pay_income_days[:w2])
      raise ArgumentError.new("Client Agency #{@id} invalid value for pay_income_days.gig") unless VALID_PAY_INCOME_DAYS.include?(@pay_income_days[:gig])
      raise ArgumentError.new("Client Agency #{@id} missing required attribute `transmission_method`") if @transmission_method.blank?
    end
  end
end
