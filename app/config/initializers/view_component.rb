if defined?(ViewComponent)
  ViewComponent::Base.config.tap do |config|
    config.previews.paths ||= []
    config.previews.paths << Rails.root.join("spec", "components", "previews")
    config.previews.default_layout = "component_preview"
  end
end
