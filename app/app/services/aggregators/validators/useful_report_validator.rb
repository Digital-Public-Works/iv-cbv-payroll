module Aggregators::Validators
  # This validator checks for presence of fields that we've determined are
  # necessary for a report to be useful to eligibility workers.
  class UsefulReportValidator < ActiveModel::Validator
    def validate(report)
      report.errors.add(:identities, "No identities present") unless report.identities.present?
      report.identities.each { |i| validate_identity(report, i) }

      report.errors.add(:employments, "No employments present") unless report.employments.present?
      report.employments.each { |e| validate_employment(report, e) }


      return false if report.errors.present?

      # Being extra-explicit about these definitions to enhance readability
      is_gig_worker = report.employments.any? { |e| e.employment_type == :gig }
      return true if is_gig_worker

      # This is a report for a W-2 employee.
      return true if has_valid_paystub?(report)

      # This logic is a heuristic to determine whether the user logged into the wrong payroll account.
      # Also checks whether they have logged in as a brand-new employee who has not received a paystub yet..
      # Summary: if you don't have any valid paystubs, either your paystubs are all too old and outside the
      # retrieval window, or you just started and have not received a paystub yet.
      if !has_paystubs?(report) || !has_valid_paystub?(report)
        return true if has_recent_termination_date?(report)

        return true if has_recent_start_date?(report)
      end

      report.errors.add(:base, "Invalid report: probably had no valid paystubs for the logged-in account (likely ADP). Look at AggregatorReport::find_account_report where paystubs get filtered.")
      report.errors.add(:base, %Q(# of paystubs: #{report&.paystubs&.size}, # of valid paystubs: #{valid_paystubs(report)&.size}))

      false
    end

    private

    def paystubs_for_account(report, account_id)
      report.paystubs.select { |paystub| paystub.account_id == account_id }
    end

    def validate_identity(report, identity)
      report.errors.add(:identities, "Identity has no full_name") unless identity.full_name.present?
    end

    def validate_employment(report, employment)
      report.errors.add(:employments, "Employment has no employer_name") unless employment.employer_name.present?
    end

    def has_recent_termination_date?(report)
      report.employments.compact.map(&:termination_date).any? { |termination_date| before_or_equal?(18.months.ago, safe_parse_date(termination_date)) }
    end

    def has_recent_start_date?(report)
      report.employments.compact.map(&:start_date).any? { |start_date| start_date.present? && before_or_equal?(46.days.ago, safe_parse_date(start_date)) }
    end

    # str_date will look something like: "2025-11-17"
    def safe_parse_date(str_date)
      Date.parse(str_date).to_date rescue nil
    end

    # returns true iff the date represented by check_date is before (in time) reference_date
    def before_or_equal?(check_date, reference_date)
      return false if check_date.blank? || reference_date.blank?

      check_date <= reference_date
    end

    def validate_paystubs(report)
      report.errors.add(:paystubs, "No paystub has pay_date") unless report.paystubs.any? { |paystub| paystub.pay_date.present? }
      report.errors.add(:paystubs, "No paystub has gross_pay_amount") unless report.paystubs.any? { |paystub| paystub.gross_pay_amount.present? }
      report.errors.add(:paystubs, "No paystub has valid gross_pay_amount") unless report.paystubs.any? { |paystub| paystub.gross_pay_amount.to_f > 0 }
    end

    def has_paystubs?(report)
      !report&.paystubs&.compact&.empty?
    end

    def has_valid_paystub?(report)
      valid_paystubs(report).present?
    end

    def valid_paystubs(report)
      report&.paystubs&.select { |paystub| valid_paystub?(paystub) }
    end

    def valid_paystub?(paystub)
      has_pay_date?(paystub) && (has_gross_pay?(paystub) || has_nonzero_hours?(paystub))
    end

    def has_pay_date?(paystub)
      paystub.pay_date.present?
    end

    def has_gross_pay?(paystub)
      paystub.gross_pay_amount.present? && paystub.gross_pay_amount.to_f > 0
    end

    def has_nonzero_hours?(paystub)
      paystub.hours.to_f > 0
    end
  end
end
