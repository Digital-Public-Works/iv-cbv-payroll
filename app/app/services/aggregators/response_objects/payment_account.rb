module Aggregators::ResponseObjects
  PAYMENT_ACCOUNT_FIELDS = %i[
    account_type
    last_four
  ]

  # Represents a single destination a paycheck is sent to (a bank account via
  # ACH, or a payout card). `account_type` holds the raw Argyle type; the
  # `category` reader translates it into the simplified "ach"/"card" buckets
  # the UI and JSON output care about.
  PaymentAccount = Struct.new(*PAYMENT_ACCOUNT_FIELDS, keyword_init: true) do
    # Argyle paystub "destinations" don't carry an explicit type field — the
    # category is implied by which sub-object is populated (ach_deposit_account
    # vs card). We store that key as the raw account_type.
    ACH_ACCOUNT_TYPE = "ach_deposit_account"
    CARD_ACCOUNT_TYPE = "card"

    CATEGORY_BY_ACCOUNT_TYPE = {
      ACH_ACCOUNT_TYPE => "ach",
      CARD_ACCOUNT_TYPE => "card"
    }.freeze

    # Builds a PaymentAccount from a single Argyle paystub "destination".
    # Returns nil when the destination has no usable (digit-bearing) account number.
    def self.from_argyle(destination)
      return if destination.blank?

      if destination[ACH_ACCOUNT_TYPE].present?
        build(ACH_ACCOUNT_TYPE, destination.dig(ACH_ACCOUNT_TYPE, "account_number"))
      elsif destination[CARD_ACCOUNT_TYPE].present?
        build(CARD_ACCOUNT_TYPE, destination.dig(CARD_ACCOUNT_TYPE, "number"))
      end
    end

    def self.build(account_type, raw_number)
      last_four = raw_number.to_s.gsub(/\D/, "").last(4).presence
      return if last_four.blank?

      new(account_type: account_type, last_four: last_four)
    end

    # Translates the raw Argyle account type into the category we display:
    # "ach" for direct-deposit bank accounts, "card" for payout cards.
    def category
      CATEGORY_BY_ACCOUNT_TYPE[account_type]
    end

    def ach?
      category == "ach"
    end

    def card?
      category == "card"
    end

    # Shape used in the JSON income report sent to agency partners.
    def to_output
      { type: category, last_four: last_four }
    end
  end
end
