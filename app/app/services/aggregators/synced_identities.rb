# used for applicant attribute prefill, if present in payroll aggregator response

module Aggregators
  class SyncedIdentities
    include Cbv::AggregatorDataHelper

    # track what we already have, so we don't need to get it again
    def initialize(cbv_flow, already_fetched: {})
      @cbv_flow = cbv_flow
      @already_fetched = already_fetched || {}
    end

    def call
      accounts = @cbv_flow.payroll_accounts.includes(:webhook_events)
      return [] if accounts.empty?
      return [] unless accounts.all?(&:has_fully_synced?)

      accounts.flat_map { |account| @already_fetched[account.id] || identities_for(account) }.compact
    end

    private

    def identities_for(account)
      set_aggregator_report_for_account(account)
      @aggregator_report.identities
    rescue StandardError => e
      Rails.logger.error("Could not read identities for payroll account #{account.id}: #{e.message}")
      []
    end

    def agency_config
      ClientAgencyConfig.instance
    end
  end
end
