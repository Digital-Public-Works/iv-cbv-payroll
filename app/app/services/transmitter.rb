# frozen_string_literal: true

module Transmitter
  attr_reader :current_agency, :cbv_flow, :aggregator_report, :transmission_config
  def initialize(cbv_flow, current_agency, aggregator_report, transmission_config = {})
    @cbv_flow = cbv_flow
    @current_agency = current_agency
    @aggregator_report = aggregator_report
    @transmission_config = transmission_config.with_indifferent_access
  end

  def deliver
    raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
  end
end
