class Report::EmploymentDetailsTableComponent< ViewComponent::Base
  include ReportViewHelper
  include Cbv::MonthlySummaryHelper

  attr_reader :employer_name

  def initialize(report, payroll_account, is_responsive: true, show_identity: false, show_income: false)
    @show_identity = show_identity
    @show_income = show_income
    @is_responsive = is_responsive
    @payroll_account = payroll_account
    @report = report

    account_report = find_account_report(report)
    @employment = account_report&.employment
    @income = account_report&.income
    @identity = account_report&.identity
    @paystubs = account_report&.paystubs
  end

  def base_pay_match
    Aggregators::AggregatorReports::Argyle::BasePayRateConsistencyChecker.new(income: @income, paystubs: paystubs_in_range).match?
  end

  private

  def paystubs_in_range
    return @paystubs if @paystubs.nil?

    from = parse_date_safely(@report.from_date)
    to = parse_date_safely(@report.to_date)
    @paystubs.select { |paystub| parse_date_safely(paystub.pay_date)&.between?(from, to) }
  end

  def has_income_data?
    @payroll_account.job_succeeded?("income")
  end

  def find_account_report(report)
    # Note: payroll_account may either be the ID or the payroll_account object
    account_id = @payroll_account.class == String ? @payroll_account : @payroll_account.aggregator_account_id
    report.find_account_report(account_id)
  end
end
