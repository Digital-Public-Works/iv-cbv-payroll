# frozen_string_literal: true

# Shared paystub-PDF generation for transmitters that honor the
# include_paystubs partner config (Argyle only).
# SharedEmailTransmitter intentionally does NOT include this mixin.
module Transmitters
  module Concerns
    module PaystubsOutput
      def paystubs_output
        return nil unless @current_agency.include_paystubs

        @_paystubs_output ||= Aggregators::PaystubsPdfService.new(
          cbv_flow: @cbv_flow,
          argyle_service: Aggregators::Sdk::ArgyleService.new(@current_agency.argyle_environment)
        ).generate
      end
    end
  end
end
