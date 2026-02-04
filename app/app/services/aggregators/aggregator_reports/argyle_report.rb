module Aggregators::AggregatorReports
  class ArgyleReport < AggregatorReport
    include Aggregators::ResponseObjects
    include ActiveModel::Validations
    include ActiveModel::Validations::Callbacks
    include Warnable

    validates_with Aggregators::Validators::UsefulReportValidator, on: :useful_report

    def initialize(argyle_service: nil, **params)
      super(**params)
      @argyle_service = argyle_service
    end

    private

    def fetch_report_data_for_account(payroll_account)
      identities_json = @argyle_service.fetch_identities_api(
        account: payroll_account.aggregator_account_id
      )

      # Override the date range to fetch when fetching a gig job.
      has_gig_job = identities_json["results"].any? do |identity_json|
        Aggregators::FormatMethods::Argyle.employment_type(identity_json["employment_type"]) == :gig
      end
      if has_gig_job
        @fetched_days = @days_to_fetch_for_gig
      end

      account_json = @argyle_service.fetch_account_api(
        account: payroll_account.aggregator_account_id
      )
      paystubs_json = @argyle_service.fetch_paystubs_api(
        account: payroll_account.aggregator_account_id,
        from_start_date: from_date,
        to_start_date: to_date
      )
      gigs_json = @argyle_service.fetch_gigs_api(
        account: payroll_account.aggregator_account_id,
        from_start_datetime: from_date,
        to_start_datetime: to_date
      )

      @identities.append(*transform_identities(identities_json))
      @employments.append(*transform_employments(identities_json,
                                                 paystubs_json,
                                                 account_json))
      @incomes.append(*transform_incomes(identities_json))
      @paystubs.append(*transform_paystubs(paystubs_json))
      @gigs.append(*transform_gigs(gigs_json))

      check_hours(paystubs_json)

      if self.has_warnings?
        NewRelic::Agent.record_custom_event(TrackEvent::ArgyleDataUnexpectedHours, {
          time: Time.now.to_i,
          cbv_flow_id: payroll_account&.cbv_flow_id,
          warnings: self.warnings.full_messages.join(", ")
        })
      end
    end

    def transform_identities(identities_json)
      identities_json["results"].map do |identity_json|
        Identity.from_argyle(identity_json)
      end
    end

    def transform_employments(identities_json, paystubs_json, account_json)
      identities_json["results"].map do |identity_json|
        Employment.from_argyle(identity_json, paystubs_json, account_json)
      end
    end

    def transform_incomes(identities_json)
      identities_json["results"].map do |identity_json|
        Income.from_argyle(identity_json)
      end
    end

    def transform_paystubs(paystubs_json)
      paystubs_json["results"].map do |paystub_json|
        Paystub.from_argyle(paystub_json)
      end
    end

    def check_hours(paystubs_json)
      paystubs_json["results"].each do |ps|
        raw_hours_valid = valid_hours_value?(ps["hours"])
        all_gross_hours_valid = ps["gross_pay_list"]&.all? { |gp| valid_hours_value?(gp["hours"]) }
        if !raw_hours_valid || !all_gross_hours_valid
          self.warnings.add(:hours, "Invalid value received for hours.")
        end
      end
    end

    def valid_hours_value?(hours)
      (0..10_000).cover?(Float(hours, exception: false))
    end

    def transform_gigs(gigs_json)
      gigs_json["results"].map do |gig_json|
        Gig.from_argyle(gig_json)
      end
    end
  end
end
