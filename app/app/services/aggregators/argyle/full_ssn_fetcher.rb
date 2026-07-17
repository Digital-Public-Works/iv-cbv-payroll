module Aggregators
  module Argyle
    class FullSsnFetcher
      AUDIT_EVENT = "full_ssn_fetched".freeze

      def initialize(argyle_service:, event_logger: GenericEventTracker.new)
        @argyle_service = argyle_service
        @event_logger = event_logger
      end

      def fetch(account_id:, cbv_flow_id:, client_agency_id:)
        raise ArgumentError, "account_id is required" if account_id.blank?

        response = @argyle_service.fetch_identities_api(account: account_id)
        raw_ssn = response.dig("results", 0, "ssn").presence
        track(
          cbv_flow_id: cbv_flow_id,
          client_agency_id: client_agency_id,
          account_id: account_id,
          success: !raw_ssn.nil?
        )

        raw_ssn
      rescue StandardError => e
        NewRelic::Agent.notice_error(e, custom_params: {
          cbv_flow_id: cbv_flow_id,
          client_agency_id: client_agency_id,
          aggregator_account_id: account_id
        })

        track(
          cbv_flow_id: cbv_flow_id,
          client_agency_id: client_agency_id,
          account_id: account_id,
          success: false,
          error_class: e.class.name
        )
      end

      private

      def track(cbv_flow_id:, client_agency_id:, account_id:, success:, error_class: nil)
        @event_logger.track(
          AUDIT_EVENT,
          nil,
          time: Time.now.to_i,
          cbv_flow_id: cbv_flow_id,
          client_agency_id: client_agency_id,
          aggregator_account_id: account_id,
          success: success,
          error_class: error_class
        )
      end
    end
  end
end
