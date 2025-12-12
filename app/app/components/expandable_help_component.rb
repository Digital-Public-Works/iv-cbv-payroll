# frozen_string_literal: true

class ExpandableHelpComponent < ViewComponent::Base
  attr_reader :id, :trigger_label, :heading, :element_name, :margin_class

  def initialize(id:, trigger_label:, heading:, element_name:, margin_class: "margin-top-2")
    @id = id
    @trigger_label = trigger_label
    @heading = heading
    @element_name = element_name
    @margin_class = margin_class
  end

  def content_id
    "#{id}-content"
  end

  def heading_id
    "#{id}-heading"
  end
end
