# frozen_string_literal: true

class ExpandableHelpComponent < ViewComponent::Base
  attr_reader :id, :trigger_label, :heading, :element_name, :track_event, :margin_class

  def initialize(id:, trigger_label:, heading: nil, element_name:, track_event: nil, margin_class: "margin-top-2", html_options: {})
    @id = id
    @trigger_label = trigger_label
    @heading = heading
    @element_name = element_name
    @track_event = track_event
    @margin_class = margin_class
    @html_options = html_options
  end

  def content_id
    "#{id}-content"
  end

  def heading_id
    "#{id}-heading"
  end

  def data_attributes
    return default_html_options[:data] if @html_options[:data].blank?

    default_html_options[:data].merge(@html_options[:data]) || {}
  end

  private
  def default_html_options
    { data: { controller: "accordion" } }
  end
end
