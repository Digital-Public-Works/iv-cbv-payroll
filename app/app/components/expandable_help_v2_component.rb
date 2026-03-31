# frozen_string_literal: true

class ExpandableHelpV2Component < ViewComponent::Base
  attr_reader :id, :trigger_label, :heading, :element_name, :track_event, :margin_class

  def initialize(id:, trigger_label:, heading: nil, element_name:, track_event: nil, margin_class: "margin-top-2", data_options: {})
    @id = id
    @trigger_label = trigger_label
    @heading = heading
    @element_name = element_name
    @track_event = track_event
    @margin_class = margin_class
    @data_options = data_options
  end

  def content_id
    "#{id}-content"
  end

  def heading_id
    "#{id}-heading"
  end

  def combined_data_attributes
    combined_options = default_data_options

    # These keys need to not be overwritten by merge with the inputted data options.
    additive_keys = [ :controller ]
    additive_keys.each do |key|
      if @data_options[:controller].present?
        combined_options[:controller] = "#{combined_options[:controller]} #{@data_options[:controller]}"
      end
    end

    combined_options.merge!(@data_options.except(*(additive_keys)))
  end

  private
  def default_data_options
    # Add keys for any other default data attributes to the additive_keys line above.
    { controller: "accordion" }
  end
end
