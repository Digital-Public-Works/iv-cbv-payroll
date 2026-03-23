class CbvFlowToJson
  PAY_FREQUENCY_MAP = {
    "biweekly" => "BIWEEKLY",
    "semimonthly" => "SEMIMONTHLY",
    "annual" => "ANNUALLY",
    "weekly" => "WEEKLY",
    "monthly" => "MONTHLY",
    "semiweekly" => "SEMIWEEKLY",
    "daily" => "DAILY",
    "hourly" => "HOURLY",
    "variable" => "VARIABLE",
    "quarterly" => "QUARTERLY"
  }.freeze

  COMPENSATION_UNIT_MAP = {
    "per_hour" => "HOURLY",
    "per_week" => "WEEKLY",
    "per_month" => "MONTHLY",
    "per_year" => "ANNUAL",
    "salary" => "SALARY",
    "hourly" => "HOURLY",
    "weekly" => "WEEKLY",
    "monthly" => "MONTHLY",
    "annual" => "ANNUAL"
  }.freeze

  DEDUCTION_TYPE_MAP = {
    "pre_tax" => "PRETAX",
    "post_tax" => "POSTTAX",
    "unknown" => "UNKNOWN"
  }.freeze

  MONTH_ABBREVIATIONS = {
    1 => "JAN", 2 => "FEB", 3 => "MAR", 4 => "APR",
    5 => "MAY", 6 => "JUN", 7 => "JUL", 8 => "AUG",
    9 => "SEP", 10 => "OCT", 11 => "NOV", 12 => "DEC"
  }.freeze

  def initialize(cbv_flow, current_agency, aggregator_report)
    @cbv_flow = cbv_flow
    @current_agency = current_agency
    @aggregator_report = aggregator_report
  end

  def to_h
    {
      report_metadata: build_report_metadata,
      client_information: build_client_information,
      employment_records: build_employment_records
    }
  end

  private

  def build_report_metadata
    {
      confirmation_code: @cbv_flow.confirmation_code,
      report_date_range: {
        start_date: @aggregator_report.from_date.strftime("%Y-%m-%d"),
        end_date: @aggregator_report.to_date.strftime("%Y-%m-%d")
      },
      consent_timestamp_utc: @cbv_flow.consented_to_authorized_use_at&.utc&.iso8601
    }
  end

  def build_client_information
    # get all configured agency partner metadata properties
    agency_partner_metadata = CbvApplicant.build_agency_partner_metadata(@current_agency.id) do |attr|
      @cbv_flow.cbv_applicant.public_send(attr)
    end

    agency_partner_metadata.merge(
      additional_jobs_to_report: @cbv_flow.has_other_jobs
    )
  end

  def build_employment_records
    monthly_summaries = @aggregator_report.summarize_by_month

    @aggregator_report.summarize_by_employer.map do |account_id, summary|
      build_employment_record(account_id, summary, monthly_summaries[account_id] || {})
    end
  end

  def build_employment_record(account_id, summary, account_monthly_summaries)
    employment = summary[:employment]
    identity = summary[:identity]
    income = summary[:income]
    employment_type = employment&.employment_type.to_s.upcase

    record = {
      employment_type: employment_type,
      employer_information: {
        employer_name: employment&.employer_name,
        employer_phone: employment&.employer_phone_number,
        employer_address: nil
      },
      employment_status: employment&.status&.upcase,
      employment_start_date: employment&.start_date,
      employment_end_date: employment&.termination_date,
      employee_information: {
        full_name: identity&.full_name,
        ssn: identity&.ssn
      },
      pay_frequency: PAY_FREQUENCY_MAP[income&.pay_frequency],
      base_compensation: {
        rate: cents_to_dollars(income&.compensation_amount),
        interval: COMPENSATION_UNIT_MAP[income&.compensation_unit]
      }
    }

    if employment_type == "W2"
      record[:w2_monthly_summaries] = build_w2_monthly_summaries(account_monthly_summaries)
      record[:w2_payments] = build_w2_payments(summary[:paystubs] || [])
      record[:gig_monthly_summaries] = nil
      record[:gig_payments] = nil
    elsif employment_type == "GIG"
      record[:gig_monthly_summaries] = build_gig_monthly_summaries(account_monthly_summaries)
      record[:gig_payments] = build_gig_payments(summary[:gigs] || [])
      record[:w2_monthly_summaries] = nil
      record[:w2_payments] = nil
    end

    record
  end

  def build_w2_monthly_summaries(account_monthly_summaries)
    account_monthly_summaries.map do |month_string, month_data|
      month_date = Date.strptime(month_string, "%Y-%m")
      partial = month_data[:partial_month_range]

      {
        month: month_date.month,
        year: month_date.year.to_s,
        total_hours: month_data[:total_w2_hours],
        number_of_paychecks: month_data[:paystubs].size,
        gross_income: cents_to_dollars(month_data[:accrued_gross_earnings]),
        partial_month: partial&.dig(:is_partial_month) || false,
        partial_month_start: partial&.dig(:included_range_start)&.to_s,
        partial_month_end: partial&.dig(:included_range_end)&.to_s
      }
    end
  end

  def build_gig_monthly_summaries(account_monthly_summaries)
    account_monthly_summaries.map do |month_string, month_data|
      month_date = Date.strptime(month_string, "%Y-%m")

      {
        month: MONTH_ABBREVIATIONS[month_date.month],
        year: month_date.year.to_s,
        total_hours: month_data[:total_gig_hours],
        gross_earnings: cents_to_dollars(month_data[:accrued_gross_earnings]),
        mileage_expenses: [
          {
            miles: month_data[:total_mileage],
            rate: nil
          }
        ]
      }
    end
  end

  def build_w2_payments(paystubs)
    paystubs.map do |paystub|
      {
        pay_date: paystub.pay_date,
        pay_period: {
          start: paystub.pay_period_start,
          end: paystub.pay_period_end
        },
        gross_pay: cents_to_dollars(paystub.gross_pay_amount) || 0,
        net_pay: cents_to_dollars(paystub.net_pay_amount) || 0,
        hours_worked: paystub.hours,
        base_hours_paid: paystub.hours,
        gross_pay_ytd: cents_to_dollars(paystub.gross_pay_ytd) || 0,
        gross_pay_line_items: build_earnings(paystub.earnings || []),
        deductions: build_deductions(paystub.deductions || [])
      }
    end
  end

  def build_gig_payments(gigs)
    gigs.map do |gig|
      {
        pay_date: gig.end_date,
        amount: cents_to_dollars(gig.compensation_amount)
      }
    end
  end

  def build_earnings(earnings)
    earnings.map do |earning|
      {
        name: earning.name,
        amount: cents_to_dollars(earning.amount)
      }
    end
  end

  def build_deductions(deductions)
    deductions.map do |deduction|
      {
        name: deduction.category,
        amount: cents_to_dollars(deduction.amount),
        type: DEDUCTION_TYPE_MAP[deduction.try(:tax)] || "UNKNOWN"
      }
    end
  end

  def cents_to_dollars(amount)
    return nil if amount.nil?
    (amount.to_f / 100).round(2)
  end
end
