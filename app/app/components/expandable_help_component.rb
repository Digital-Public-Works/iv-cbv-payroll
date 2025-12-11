# frozen_string_literal: true

class ExpandableHelpComponent < ViewComponent::Base
  attr_reader :id, :trigger_label, :heading, :track_name, :tabindex, :margin_class

  def initialize(id:, trigger_label:, heading:, track_name:, tabindex: nil, margin_class: "margin-top-2")
    @id = id
    @trigger_label = trigger_label
    @heading = heading
    @track_name = track_name
    @tabindex = tabindex
    @margin_class = margin_class
  end

  def content_id
    "#{id}-content"
  end

  def heading_id
    "#{id}-heading"
  end
end
