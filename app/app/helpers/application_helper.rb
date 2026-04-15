module ApplicationHelper
  class MissingAgencyTranslation < RuntimeError; end

  def current_agency?(client_agency_id)
    return false if current_agency.nil?

    current_agency.id.to_sym == client_agency_id.to_sym
  end

  # Render a translation that is specific to the current client agency. Define
  # client agency-specific translations as:
  #
  # foo:
  #   az_des: Some String
  #   la_ldh: Other String
  #   default: Default String
  #
  # Then call this method with, `agency_translation("foo")` and it will attempt
  # to render the nested translation according to the client agency returned by a
  # `current_agency` method defined by your controller/mailer. If the translation
  # is either missing or there is no current client agency, it will attempt to render a
  # "default" key.
  # Like agency_translation but returns nil instead of raising when the translation is missing.
  # Use for optional translations like help_text that may not exist for every field.
  def agency_translation_if_exists(i18n_base_key, **options)
    agency_translation(i18n_base_key, **options)
  rescue MissingAgencyTranslation
    nil
  end

  def agency_translation(i18n_base_key, **options)
    if i18n_base_key.include?("{agency}")
      i18n_key = current_agency ? i18n_base_key.gsub("{agency}", current_agency.id) : nil
      default_key = i18n_base_key.gsub("{agency}", "default")
    else
      default_key = "#{i18n_base_key}.default"
      i18n_key =
        if current_agency
          "#{i18n_base_key}.#{current_agency.id}"
        else
          default_key
        end
    end
    is_html_key = /(?:_|\b)html\z/.match?(i18n_base_key)
    if is_html_key
      options.each do |name, value|
        next if name == :count && value.is_a?(Numeric)

        # Sanitize values being interpolated into this string.
        options[name] = ERB::Util.html_escape(value.to_s)
      end
    end

    # Look for the translation in the database first; if not found there, look in the locale files.
    translated = db_translation(i18n_key, **options) || db_translation(i18n_base_key, **options)

    translated ||= if I18n.exists?(scope_key_by_partial(i18n_key))
                     t(i18n_key, **options)
                   elsif I18n.exists?(scope_key_by_partial(default_key))
                     t(default_key, **options)
                   end

    if translated.blank? && Rails.env.development?
      raise MissingAgencyTranslation, "Missing agency translation: #{i18n_key} (base: #{i18n_base_key}, default: #{default_key})"
    end

    # Mark as html_safe if the base key ends with `_html`.
    #
    # We have to replicate the logic from ActiveSupport::HtmlSafeTranslation
    # because the base key is the one that ends with "_html", not the one we
    # ultimately pass into the translation library.
    if is_html_key && translated.present?
      translated.html_safe
    else
      translated
    end
  end

  private

  # db translations should be forgiving on the keys used.
  # For example, we should be able to find a value under shared.agency_portal_name or shared.agency_portal_name.default or shared.agency_portal_name.{partner_id}.
  # This means that in the relevant value columns, values can be entered naturally, or with a suffix that would be added by agency_translation.
  # The options argument allows the caller to specify a hash for replacing values into %{key} placeholders in the translation string.
  def db_translation(base_key, **options)
    return nil unless current_agency && partner_translations_table_exists?

    partner_config = cached_partner_config(current_agency.id)
    return nil unless partner_config

    locale = I18n.locale.to_s
    cache_key = PartnerTranslation.cache_key_for(partner_config.id, locale, base_key)

    value = Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
      translation = PartnerTranslation.find_by(
        partner_config: partner_config,
        locale: locale,
        key: base_key
      )

      if translation.nil? && base_key.end_with?(".#{partner_config.partner_id}")
        translation = PartnerTranslation.find_by(
          partner_config: partner_config,
          locale: locale,
          key: base_key.delete_suffix(".#{partner_config.partner_id}")
        )
      end

      if translation.nil? && base_key.end_with?(".default")
        translation = PartnerTranslation.find_by(
          partner_config: partner_config,
          locale: locale,
          key: base_key.delete_suffix(".default")
        )
      end

      translation&.value
    end

    return nil unless value

    value = value.dup

    options.each { |k, v| value = value.gsub("%{#{k}}", v.to_s) } if options.any?
    value
  end

  def partner_translations_table_exists?
    @@partner_translations_table_exists ||= ActiveRecord::Base.connection.data_source_exists?(:partner_translations)
  end

  def cached_partner_config(partner_id)
    Rails.cache.fetch("partner_config/#{partner_id}", expires_in: 10.minutes) do
      PartnerConfig.find_by(partner_id: partner_id)
    end
  end

  public

  APPLICANT_FEEDBACK_FORM = "https://docs.google.com/forms/d/e/1FAIpQLSedCtd9Jnyr41dAAQf3jSyhxqcqRrpaDIUI9DcH300Tg53ygA/viewform"
  APPLICANT_SURVEY_FORM = "https://docs.google.com/forms/d/e/1FAIpQLSedCtd9Jnyr41dAAQf3jSyhxqcqRrpaDIUI9DcH300Tg53ygA/viewform"

  def feedback_form_url
    APPLICANT_FEEDBACK_FORM
  end

  def survey_form_url
    APPLICANT_SURVEY_FORM
  end

  # some job statuses we consider completed even if they failed
  def coalesce_to_completed(status)
    [ :unsupported, :failed ].include?(status) ? :completed : status
  end

  def uswds_form_with(model: false, scope: nil, url: nil, format: nil, **options, &block)
    options[:builder] = UswdsFormBuilder
    options[:data] ||= {}
    options[:data][:turbo_frame] = "_top"

    turbo_frame_tag(model) do
      form_with(model: model, scope: scope, url: url, format: format, **options, &block)
    end
  end

  def date_string_to_date(date_string)
    date_string.is_a?(Date) ? date_string : Date.strptime(date_string, "%Y-%m-%d")
  rescue
    nil
  end

  def get_age_range(date_of_birth, now: Date.today)
    dob = date_string_to_date(date_of_birth)
    return nil unless dob

    age = now.year - dob.year
    this_years_birthday = Date.new(now.year, dob.month, dob.day)

    # Subtract 1 if birthday hasn't occurred yet this year
    age -= 1 if now < this_years_birthday

    case age
    when 0..18 then "0-18"
    when 19..25 then "19-25"
    when 26..29 then "26-29"
    when 30..39 then "30-39"
    when 40..49 then "40-49"
    when 50..54 then "50-54"
    when 55..59 then "55-59"
    when 60..64 then "60-64"
    when 65..69 then "65-69"
    when 70..74 then "70-74"
    when 75..79 then "75-79"
    when 80..89 then "80-89"
    when 90.. then "90+"
    end
  end
end
