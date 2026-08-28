# frozen_string_literal: true

class LinkWithIconComponent < ViewComponent::Base
  def initialize(text, url:, icon: nil, variant: nil, icon_position: :leading, **options)
    @text = text
    @url = url
    @variant = variant
    @options = options
    apply_new_tab_defaults = icon.nil? && opens_in_new_tab?
    @icon = apply_new_tab_defaults ? "launch" : icon
    @icon_position = apply_new_tab_defaults ? :trailing : icon_position
  end

  private

  attr_reader :text, :url, :icon, :variant, :icon_position, :options

  def link_classes
    classes = [ "usa-link" ]
    if variant
      Array(variant).each do |v|
        classes << "usa-link--#{v.to_s.dasherize}"
      end
    end
    custom_class = options[:class]
    classes << custom_class if custom_class
    classes.join(" ")
  end

  def link_options
    options.except(:class).merge(class: link_classes)
  end

  def icon_svg
    return unless icon
    icon_sprite_path = helpers.asset_path("@uswds/uswds/dist/img/sprite.svg")
    icon_path = "#{icon_sprite_path}##{icon}"
    content_tag(:svg, class: "usa-icon", "aria-hidden": true, focusable: false, role: "img") do
      tag.use("", href: icon_path)
    end
  end

  def leading_icon?
    icon_position == :leading
  end

  def trailing_icon?
    icon_position == :trailing
  end

  def opens_in_new_tab?
    options[:target] == "_blank"
  end

  def new_tab_sr_text
    return unless opens_in_new_tab?
    helpers.sr_only_span(I18n.t("shared.opens_in_new_tab"))
  end
end
