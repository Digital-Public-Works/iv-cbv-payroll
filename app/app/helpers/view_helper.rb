module ViewHelper
  def switch_locale_link(locale)
    new_locale = locale == I18n.default_locale ? nil : locale
    # user supplied query params go through 'params' so they cannot point user off site
    path = url_for(
      request.path_parameters.merge(
        locale: new_locale,
        only_path: true,
        params: request.query_parameters.except("locale")
      )
    )
    link_to t("shared.languages.#{locale}"), path, class: "usa-nav__link", data: { "turbo-prefetch": false, "action": "click->language#switchLocale", "locale": locale }
  end
end
