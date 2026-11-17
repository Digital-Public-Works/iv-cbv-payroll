module ViewHelper
  def switch_locale_link(locale)
    new_locale = locale == I18n.default_locale ? nil : locale
    safe_params = request.params.to_unsafe_h.except(:host, :port, :protocol, :script_name, :original_script_name, :anchor, :params, :trailing_slash)
    path = url_for(safe_params.merge(locale: new_locale, only_path: true))
    link_to t("shared.languages.#{locale}"), path, class: "usa-nav__link", data: { "turbo-prefetch": false, "action": "click->language#switchLocale", "locale": locale }
  end
end
