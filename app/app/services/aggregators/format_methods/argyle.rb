module Aggregators::FormatMethods::Argyle
  MILES_PER_KM = 0.62137

  # Note: this method is to map Argyle's employment status with Pinwheel's for consistency
  # between the two providers.
  def self.format_employment_status(employment_status)
    return unless employment_status

    case employment_status
    when "active"
      "employed"
    else
      employment_status
    end
  end

  def self.format_mileage(distance_string, distance_unit = "miles")
    return nil if distance_string.blank?
    distance = distance_string.to_f
    if distance_unit == "km"
      distance = distance * MILES_PER_KM
    end
    distance
  end

  def self.format_date(date)
    return unless date

    DateTime.parse(date).strftime("%Y-%m-%d")
  end

  def self.format_currency(amount)
    return unless amount
    dollars, cents = amount.split(".").map(&:to_i)

    (dollars * 100) + cents
  end

  def self.hours_computed(response_hours, response_gross_pay_list)
    if response_hours.present? && response_hours.to_f > 0
      response_hours.to_f
    else
      synthetic_hours(response_gross_pay_list)
    end
  end

  # Calculates total hours when Argyle does not provide a total hours value.
  def self.synthetic_hours(gross_pay_list)
    hours_by_category = hours_by_earning_category(gross_pay_list)

    # Because Argyle labeling is imperfect, we have determined that
    # the base pay is likely whatever category has the most hours worked.
    base_hours = hours_by_category
      .reject { |category, _| category == "overtime" }
      .map { |_, hours| hours.to_f }
      .max

    overtime_hours = overtime_worked_hours(gross_pay_list)
    total = (base_hours || 0) + overtime_hours
    total > 0 ? total : nil
  end

  # Determines how many overtime hours represent actual additional hours worked
  # (as opposed to supplemental pay on top of already-counted hours).
  #
  # An overtime item's hours are "worked" if its effective rate exceeds the
  # lowest base pay rate (or the federal minimum wage, whichever is higher).
  # A rate above that threshold indicates a true overtime multiplier (e.g. 1.5x),
  # meaning those hours are separate from base hours. A rate at or below the
  # threshold suggests a supplemental bonus (e.g. +$1/hr for holiday work)
  # where the hours are already counted in another category.
  def self.overtime_worked_hours(gross_pay_list)
    base_items = gross_pay_list.reject { |e| e["type"] == "overtime" }
    overtime_items = gross_pay_list.select { |e| e["type"] == "overtime" }

    return 0.0 if overtime_items.empty?

    lowest_base_rate = base_items
      .map { |e| implied_rate(e) }
      .compact
      .min

    rate_threshold = [ lowest_base_rate, ReportViewHelper::FEDERAL_MINIMUM_WAGE_DOLLARS ].compact.max

    overtime_items
      .select { |e| overtime_hours_are_worked?(e, rate_threshold) }
      .sum { |e| e["hours"].to_f }
  end

  # Returns true if an overtime item represents actual hours worked
  # (has hours and its rate exceeds the threshold).
  def self.overtime_hours_are_worked?(overtime_item, rate_threshold)
    rate = implied_rate(overtime_item)
    overtime_item["hours"].to_f > 0 && rate.present? && rate > rate_threshold
  end

  # Returns the per-hour rate for a pay item. Uses the explicit rate field
  # if present, otherwise calculates it as amount / hours.
  def self.implied_rate(pay_item)
    return pay_item["rate"].to_f if pay_item["rate"].present?

    hours = pay_item["hours"].presence&.to_f
    amount = pay_item["amount"].presence&.to_f
    return nil unless hours && hours > 0 && amount

    amount / hours
  end

  def self.hours_by_earning_category(gross_pay_list)
    gross_pay_list
       .filter { |e| e["hours"].present? }
       .group_by { |e| e["type"] }
       .transform_values { |earnings| earnings.sum { |e| e["hours"].to_f } }
  end

  def self.format_employer_address(a_paystub)
    return unless a_paystub.present? && a_paystub["employer_address"].present?
    employer_address = a_paystub["employer_address"]
    [
      employer_address["line1"],
      employer_address["line2"],
      "#{employer_address['city']}, #{employer_address['state']} #{employer_address['postal_code']}"
    ].compact.join(", ")
  end

  def self.direct_deposit_accounts(destinations)
    return [] if destinations.blank?

    destinations.filter_map do |destination|
      account = destination["ach_deposit_account"]
      next if account.blank?

      account["account_number"].to_s.gsub(/\D/, "").last(4).presence
    end
  end

  def self.seconds_to_hours(seconds)
    return unless seconds
    (seconds / 3600.0).round(2)
  end

  def self.employment_type(employment_type)
    if employment_type == "contractor"
      :gig
    else
      :w2
    end
  end

  def self.obfuscate_ssn(full_ssn)
    return unless full_ssn
    "XXX-XX-#{full_ssn.last(4).to_s.rjust(4, "X")}"
  end

  def self.paystub_implied_base_rate_in_dollars(paystub_response_body)
    rate_implied = paystub_response_body.dig("gross_pay_list_totals", "base", "rate_implied")

    rate_implied.presence&.to_f
  end

  def self.total_hours_match?(hours1, hours2)
    (hours1.to_f - hours2.to_f).abs < 0.01
  end
end
