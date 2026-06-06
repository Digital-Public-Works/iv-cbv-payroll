# frozen_string_literal: true

class Report::W2PaystubDetailsTableComponent < ViewComponent::Base
  include ReportViewHelper

  # @param paystub [Aggregators::ResponseObjects::Paystub] The paystub data to display
  # @param income [Aggregators::ResponseObjects::Income, nil] Income object containing pay frequency info
  # @param is_caseworker [Boolean] If true, highlights certain fields for caseworker view
  # @param is_responsive [Boolean] If true, table adapts to mobile screens.  If false, does not (e.g. PDF)
  # @param is_personalized [Boolean] If true, uses "Your details" header; if false, uses "Details"
  # @param show_hours_breakdown [Boolean] If true, shows hours by earning category (Regular, Commission, etc.)
  # @param show_gross_pay_ytd [Boolean] If true, shows gross pay year-to-date (only if value > 0)
  # @param show_pay_frequency [Boolean] If true, shows pay period with frequency
  # @param show_earnings_items [Boolean] If true, shows earnings items in a separate table at the bottom
  def initialize(
    paystub,
    income: nil,
    is_caseworker: false,
    is_responsive: true,
    is_personalized: false,
    show_hours_breakdown: true,
    show_gross_pay_ytd: true,
    show_pay_frequency: true,
    show_earnings_items: false,
    show_direct_deposit_accounts: false
  )
    @paystub = paystub
    @income = income
    @is_caseworker = is_caseworker
    @is_responsive = is_responsive
    @is_personalized = is_personalized
    @show_hours_breakdown = show_hours_breakdown
    @show_gross_pay_ytd = show_gross_pay_ytd
    @show_pay_frequency = show_pay_frequency
    @show_earnings_items = show_earnings_items
    @show_direct_deposit_accounts = show_direct_deposit_accounts
  end

  private

  def details_header
    if @is_personalized
      t("components.report.w2_paystub_details_table.your_details")
    else
      t("components.report.w2_paystub_details_table.details")
    end
  end

  def pay_frequency_text
    if @income&.pay_frequency
      @income.pay_frequency&.humanize
    else
      t("components.report.w2_paystub_details_table.frequency_unknown")
    end
  end

  def show_gross_pay_ytd?
    @show_gross_pay_ytd && @paystub.gross_pay_ytd.to_f > 0
  end

  def show_pay_frequency?
    @show_pay_frequency
  end

  def show_hours_breakdown?
    @show_hours_breakdown
  end

  def show_earnings_items?
    @show_earnings_items && @paystub.earnings.present?
  end

  def show_direct_deposit_accounts?
    @show_direct_deposit_accounts
  end

  # Builds the data-point argument lists for the direct deposit / payout card
  # rows. ACH (bank) accounts render first, then payout cards; within each type
  # the accounts are numbered only when there is more than one. When there are
  # no accounts at all, a single "No deposit accounts found" row is shown.
  def direct_deposit_account_data_points
    accounts = @paystub.direct_deposit_accounts || []
    ach_accounts = accounts.select(&:ach?)
    card_accounts = accounts.select(&:card?)

    return [ [ :no_deposit_accounts ] ] if ach_accounts.empty? && card_accounts.empty?

    account_rows(:direct_deposit_account, ach_accounts) +
      account_rows(:payout_card_account, card_accounts)
  end

  def account_rows(field, accounts)
    numbered = accounts.size > 1

    accounts.each_with_index.map do |account, index|
      if numbered
        [ field, account.last_four, index + 1 ]
      else
        [ field, account.last_four ]
      end
    end
  end

  def earnings_sort_order(earnings)
    category_order = %w[
      base
      overtime
      pto
      commission
      tips
      bonus
      benefits
      other
      disability
      stock
    ].freeze

    # Convert to a hash for O(1) lookups during sort
    category_index = category_order.each_with_index.to_h.freeze
    default_index = category_order.length + 1

    earnings.sort_by.with_index do |earning, index|
      # First, sort by category order. If equal, sort by original index
      [ category_index[earning.category&.downcase] || default_index, index ]
    end
  end

  def earning_label(earning)
    "#{t("components.report.w2_paystub_details_table.gross_pay_item_prefix")} #{earning.name}"
  end

  def paystub_heading
    "#{t("components.report.w2_paystub_details_table.paystub_heading_prefix")} #{format_date(@paystub.pay_date)}"
  end
end
