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
    combined_options = { controller: "accordion" }

    # If a controller is passed in, append to the accordion controller
    if @data_options[:controller].present?
      combined_options[:controller] += " #{@data_options[:controller]}"
    end

    combined_options.merge(@data_options.except(:controller))
  end
end
