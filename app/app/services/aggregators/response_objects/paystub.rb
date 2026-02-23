module Aggregators::ResponseObjects
  PAYSTUB_FIELDS = %i[
    account_id
    id
    gross_pay_amount
    net_pay_amount
    gross_pay_ytd
    pay_period_start
    pay_period_end
    pay_date
    deductions
    hours_by_earning_category
    hours
    earnings
    employment_id
  ]

  Paystub = Struct.new(*PAYSTUB_FIELDS, keyword_init: true) do
    def self.from_pinwheel(response_body)
      new(
        account_id: response_body["account_id"],
        gross_pay_amount: response_body["gross_pay_amount"],
        net_pay_amount: response_body["net_pay_amount"],
        gross_pay_ytd: response_body["gross_pay_ytd"],
        pay_period_start: response_body["pay_period_start"],
        pay_period_end: response_body["pay_period_end"],
        pay_date: response_body["pay_date"],
        earnings: response_body["earnings"].map { |i| Earning.from_pinwheel(i) },
        hours: Aggregators::FormatMethods::Pinwheel.hours(response_body["earnings"]),
        hours_by_earning_category: Aggregators::FormatMethods::Pinwheel.hours_by_earning_category(response_body["earnings"]),
        deductions: response_body["deductions"].map do |deduction|
          OpenStruct.new(
            category: deduction["category"],
            tax: deduction["type"] || "unknown",
            amount: deduction["amount"],
          )
        end,
        employment_id: nil # Not provided
      )
    end

    def self.from_argyle(response_body)
      begin
        self.log_paystub_to_mixpanel(response_body)
      rescue => ex
        NewRelic::Agent.notice_error(ex)
        Rails.logger.error "Error logging paystub to MixPanel: #{ex}"
      end

      new(
        id: response_body["id"],
        account_id: response_body["account"],
        gross_pay_amount: Aggregators::FormatMethods::Argyle.format_currency(response_body["gross_pay"]),
        net_pay_amount: Aggregators::FormatMethods::Argyle.format_currency(response_body["net_pay"]),
        gross_pay_ytd: Aggregators::FormatMethods::Argyle.format_currency(response_body["gross_pay_ytd"]),
        pay_period_start: Aggregators::FormatMethods::Argyle.format_date(response_body["paystub_period"]["start_date"]),
        pay_period_end: Aggregators::FormatMethods::Argyle.format_date(response_body["paystub_period"]["end_date"]),
        pay_date: Aggregators::FormatMethods::Argyle.format_date(response_body["paystub_date"]),
        earnings: response_body["gross_pay_list"].map { |i| Earning.from_argyle(i) },
        hours: Aggregators::FormatMethods::Argyle.hours_computed(response_body["hours"], response_body["gross_pay_list"]),
        hours_by_earning_category: Aggregators::FormatMethods::Argyle.hours_by_earning_category(response_body["gross_pay_list"]),
        deductions: response_body["deduction_list"].map do |deduction|
          OpenStruct.new(
            category: deduction["name"],
            tax: deduction["tax_classification"] || "unknown",
            amount: Aggregators::FormatMethods::Argyle.format_currency(deduction["amount"]),
          )
        end,
        employment_id: response_body["employment"]
      )
    end

    def self.log_paystub_to_mixpanel(response_body)
      gross_pay_total = response_body["gross_pay_list"]&.map { |item| item["hours"] || 0 }&.map(&:to_f)&.sum
      synthetic_total_hours = Aggregators::FormatMethods::Argyle.hours_by_earning_category(response_body["gross_pay_list"]).map { |_category, hours| hours.to_f }&.max

      GenericEventTracker.new.track(TrackEvent::ArgylePaystubHours, nil, {
        time: Time.now.to_i,
        argyle_total_hours: response_body["hours"],
        gross_pay_sum: gross_pay_total,
        synthetic_total_hours: synthetic_total_hours,
        argyle_total_hours_matches_synthetic: synthetic_total_hours == response_body["hours"],
        argyle_hours_null: response_body["hours"].nil?
      })
    end

    alias_attribute :start, :pay_period_start
    alias_attribute :end, :pay_period_end
  end
end
